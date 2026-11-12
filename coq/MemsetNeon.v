(* rt_memset_neon, every length that fits in x2.
   Bytes are the Mach-O text of _rt_memset_neon from
   clang -arch arm64 -c src/aarch64/neon/mem.S
   (file offsets 0x130..0x20f).
   The address space is the destination list, so the incoming pointer is 0
   and the returned pointer is 0. Checked claim: every fill byte b < 256
   and every length n < 2^64. The routine writes n copies of b and stops.
   memcpy, memcmp, and the other kernels are not claims of this file. *)

From Stdlib Require Import List NArith ZArith Bool PeanoNat Lia.
Import ListNotations.

Local Open Scope N_scope.
Local Open Scope bool_scope.

Definition mask_bits (bits : N) : N := N.pred (N.shiftl 1 bits).

Definition field (w hi lo : N) : N :=
  N.land (N.shiftr w lo) (mask_bits (hi - lo + 1)).

(* Sign-extend a [width]-bit unsigned field. *)
Definition sext (u width : N) : Z :=
  let z := Z.of_N u in
  let half := Z.shiftl 1 (Z.of_N (width - 1)) in
  let modu := Z.shiftl 1 (Z.of_N width) in
  if Z.ltb z half then z else Z.sub z modu.

(* Logical-immediate mask, 32-bit. N bit of the encoding is 0 here. *)
Fixpoint repl (welem esize : N) (n : nat) (acc : N) : N :=
  match n with
  | O => acc
  | S n =>
      repl welem esize n
        (N.lor acc (N.shiftl welem (N.mul esize (N.of_nat n))))
  end.

Definition bitmask32 (immr imms : N) : N :=
  let nimms := N.lxor imms (mask_bits 6) in
  let length := N.size nimms - 1 in
  let esize := N.shiftl 1 length in
  let levels := N.pred esize in
  let S := N.land imms levels in
  let R := N.land immr levels in
  let ones := N.pred (N.shiftl 1 (S + 1)) in
  let elim := mask_bits esize in
  let welem0 := N.land ones elim in
  let welem :=
    if N.eqb R 0 then welem0
    else
      N.land
        (N.lor (N.shiftr welem0 R) (N.shiftl welem0 (esize - R)))
        elim in
  N.land (repl welem esize (N.to_nat (N.div 32 esize)) 0) (mask_bits 32).

Inductive Insn : Type :=
| Orr : bool -> N -> N -> N -> N -> Insn   (* 64-bit?, rd, rn, rm, shift *)
| And32 : N -> N -> N -> Insn              (* rd, rn, mask *)
| AddSub : bool -> bool -> N -> N -> N -> N -> Insn
    (* sub?, flags?, width, rd, rn, imm *)
| Bcond : Z -> N -> Insn                   (* insn offset, cond *)
| Cbz : N -> Z -> Insn
| Dup2d : N -> N -> Insn                   (* vd, rn *)
| StrQ : N -> N -> Z -> Insn               (* vt, rn, post-index bytes *)
| StpQ : N -> N -> N -> Z -> Insn          (* vt, vt2, rn, byte offset *)
| StrPost : nat -> N -> N -> Z -> Insn     (* nbytes, rt, rn, post-index *)
| StrB : N -> N -> N -> Insn               (* rt, rn, unsigned byte offset *)
| Tbz : N -> N -> Z -> Insn                (* rt, bit, insn offset *)
| B : Z -> Insn
| Nop : Insn
| Ret : Insn.

Definition decode (w : N) : option Insn :=
  if N.eqb w 0xD65F03C0 then Some Ret
  else if N.eqb w 0xD503201F then Some Nop
  else if (N.eqb (field w 31 24) 0x54) && (N.eqb (field w 4 4) 0) then
    Some (Bcond (sext (field w 23 5) 19) (field w 3 0))
  else if (N.eqb (field w 31 31) 1) && (N.eqb (field w 30 25) 26)
          && (N.eqb (field w 24 24) 0) then
    Some (Cbz (field w 4 0) (sext (field w 23 5) 19))
  else if (N.eqb (field w 31 31) 0) && (N.eqb (field w 30 30) 1)
          && (N.eqb (field w 29 21) 112) && (N.eqb (field w 20 16) 8)
          && (N.eqb (field w 15 10) 3) then
    Some (Dup2d (field w 4 0) (field w 9 5))
  else if (N.eqb (field w 31 30) 0) && (N.eqb (field w 29 21) 484)
          && (N.eqb (field w 11 10) 1) then
    Some (StrQ (field w 4 0) (field w 9 5) (sext (field w 20 12) 9))
  else if N.eqb (field w 31 23) 0x15A then
    Some (StpQ (field w 4 0) (field w 14 10) (field w 9 5)
               ((sext (field w 21 15) 7) * 16)%Z)
  else if (N.eqb (field w 29 24) 0x38) && (N.eqb (field w 11 10) 1) then
    let size := field w 31 30 in
    if N.eqb size 0 then None
    else Some (StrPost (N.to_nat (N.shiftl 1 size))
                       (field w 4 0) (field w 9 5) (sext (field w 20 12) 9))
  else if N.eqb (field w 31 24) 0x39 then
    Some (StrB (field w 4 0) (field w 9 5) (field w 21 10))
  else if (N.eqb (field w 30 25) 27) && (N.eqb (field w 24 24) 0) then
    let b5 := field w 31 31 in
    Some (Tbz (field w 4 0) (field w 23 19 + b5 * 32)
              (sext (field w 18 5) 14))
  else if N.eqb (field w 31 26) 5 then
    Some (B (sext (field w 25 0) 26))
  else if (N.eqb (field w 31 31) 0) && (N.eqb (field w 30 29) 0)
          && (N.eqb (field w 28 23) 36) && (N.eqb (field w 22 22) 0) then
    Some (And32 (field w 4 0) (field w 9 5)
                (bitmask32 (field w 21 16) (field w 15 10)))
  else if (N.eqb (field w 30 29) 1) && (N.eqb (field w 28 24) 10)
          && (N.eqb (field w 21 21) 0) then
    Some (Orr (N.eqb (field w 31 31) 1) (field w 4 0) (field w 9 5)
              (field w 20 16) (field w 15 10))
  else if (N.eqb (field w 28 24) 17) && (N.eqb (field w 23 22) 0) then
    Some (AddSub (N.eqb (field w 30 30) 1) (N.eqb (field w 29 29) 1)
                 (if N.eqb (field w 31 31) 1 then 64 else 32)
                 (field w 4 0) (field w 9 5) (field w 21 10))
  else None.

(* Instruction words of _rt_memset_neon, in order. *)
Definition code : list N :=
  [ 0xAA0003E8; 0x12001C21; 0x2A012021; 0x2A014021
  ; 0xAA018023; 0x4E080C60; 0xF100405F; 0x54000463
  ; 0xF101005F; 0x54000183; 0xD503201F; 0xD503201F
  ; 0xAD000000; 0xAD010000; 0x91010000; 0xD1010042
  ; 0xF101005F; 0x54FFFF62; 0xB40002C2; 0xF100405F
  ; 0x540000C3; 0x3C810400; 0xD1004042; 0xF100405F
  ; 0x54FFFFA2; 0xB40001E2; 0xF100205F; 0x54000063
  ; 0xF8008403; 0xD1002042; 0xF100105F; 0x54000063
  ; 0xB8004403; 0xD1001042; 0xF100085F; 0x54000063
  ; 0x78002403; 0xD1000842; 0xB4000042; 0x39000003
  ; 0xAA0803E0; 0xD65F03C0; 0x36180062; 0xF8008403
  ; 0xD1002042; 0x36100062; 0xB8004403; 0xD1001042
  ; 0x36080062; 0x78002403; 0xD1000842; 0x3607FEA2
  ; 0x39000003; 0x17FFFFF3; 0xD503201F; 0xD503201F
  ].

Record Mach := Mk {
  r0 : N; r1 : N; r2 : N; r3 : N; r8 : N;
  lo : N; hi : N;
  mem : list N;
  pc : N;
  fc : bool; fz : bool;
  done : bool;
  qstore : bool
}.

Definition getr (s : Mach) (n : N) : option N :=
  match n with
  | 0 => Some s.(r0) | 1 => Some s.(r1) | 2 => Some s.(r2)
  | 3 => Some s.(r3) | 8 => Some s.(r8) | 31 => Some 0
  | _ => None
  end.

Definition setr (s : Mach) (n v : N) : option Mach :=
  match n with
  | 0 => Some (Mk v s.(r1) s.(r2) s.(r3) s.(r8) s.(lo) s.(hi) s.(mem) s.(pc) s.(fc) s.(fz) s.(done) s.(qstore))
  | 1 => Some (Mk s.(r0) v s.(r2) s.(r3) s.(r8) s.(lo) s.(hi) s.(mem) s.(pc) s.(fc) s.(fz) s.(done) s.(qstore))
  | 2 => Some (Mk s.(r0) s.(r1) v s.(r3) s.(r8) s.(lo) s.(hi) s.(mem) s.(pc) s.(fc) s.(fz) s.(done) s.(qstore))
  | 3 => Some (Mk s.(r0) s.(r1) s.(r2) v s.(r8) s.(lo) s.(hi) s.(mem) s.(pc) s.(fc) s.(fz) s.(done) s.(qstore))
  | 8 => Some (Mk s.(r0) s.(r1) s.(r2) s.(r3) v s.(lo) s.(hi) s.(mem) s.(pc) s.(fc) s.(fz) s.(done) s.(qstore))
  | 31 => Some s
  | _ => None
  end.

Definition setmem (s : Mach) (m : list N) (pc' : N) (q : bool) : Mach :=
  Mk s.(r0) s.(r1) s.(r2) s.(r3) s.(r8) s.(lo) s.(hi) m pc' s.(fc) s.(fz) s.(done) q.

Definition setpc (s : Mach) (pc' : N) : Mach :=
  Mk s.(r0) s.(r1) s.(r2) s.(r3) s.(r8) s.(lo) s.(hi) s.(mem) pc' s.(fc) s.(fz) s.(done) s.(qstore).

Definition setflags (s : Mach) (c z : bool) (pc' : N) : Mach :=
  Mk s.(r0) s.(r1) s.(r2) s.(r3) s.(r8) s.(lo) s.(hi) s.(mem) pc' c z s.(done) s.(qstore).

Definition setdup (s : Mach) (v pc' : N) : Mach :=
  Mk s.(r0) s.(r1) s.(r2) s.(r3) s.(r8) v v s.(mem) pc' s.(fc) s.(fz) s.(done) s.(qstore).

Definition setdone (s : Mach) : Mach :=
  Mk s.(r0) s.(r1) s.(r2) s.(r3) s.(r8) s.(lo) s.(hi) s.(mem) s.(pc) s.(fc) s.(fz) true s.(qstore).

Definition subm (a imm bits : N) : N :=
  let m := mask_bits bits in
  N.land (N.land a m + (m - N.land imm m) + 1) m.

Definition addm (a imm bits : N) : N :=
  let m := mask_bits bits in
  N.land (N.land a m + N.land imm m) m.

Definition orrv (a b sh bits : N) : N :=
  let m := mask_bits bits in
  N.lor (N.land a m) (N.land (N.shiftl (N.land b m) sh) m).

Fixpoint le_bytes (w : N) (n : nat) : list N :=
  match n with
  | O => []
  | S n => N.land w 255 :: le_bytes (N.shiftr w 8) n
  end.

Fixpoint write1 (m : list N) (i : nat) (b : N) : option (list N) :=
  match m with
  | [] => None
  | x :: m =>
      match i with
      | O => Some (b :: m)
      | S j => option_map (fun m' => x :: m') (write1 m j b)
      end
  end.

Fixpoint write_bytes (m : list N) (addr : nat) (bs : list N) : option (list N) :=
  match bs with
  | [] => Some m
  | b :: bs =>
      match write1 m addr b with
      | None => None
      | Some m' => write_bytes m' (S addr) bs
      end
  end.

Definition zadd (base : N) (off : Z) : N :=
  Z.to_N (Z.of_N base + off)%Z.

Definition pc_add (pc : N) (off : Z) : N :=
  zadd pc (off * 4)%Z.

Definition take_cond (c : bool) (cond : N) : option bool :=
  match cond with
  | 2 => Some c          (* b.hs *)
  | 3 => Some (negb c)   (* b.lo *)
  | _ => None
  end.

Definition word_at (pc : N) : option N :=
  if N.eqb (N.land pc 3) 0
  then nth_error code (N.to_nat (N.shiftr pc 2))
  else None.

Definition step (s : Mach) (i : Insn) : option Mach :=
  let next := s.(pc) + 4 in
  match i with
  | Ret => Some (setdone s)
  | Nop => Some (setpc s next)
  | B off => Some (setpc s (pc_add s.(pc) off))
  | Orr sf rd rn rm sh =>
      match getr s rn, getr s rm with
      | Some a, Some b =>
          let bits := if sf then 64 else 32 in
          setr (setpc s next) rd (orrv a b sh bits)
      | _, _ => None
      end
  | And32 rd rn mask =>
      match getr s rn with
      | Some a => setr (setpc s next) rd (N.land (N.land a (mask_bits 32)) mask)
      | None => None
      end
  | AddSub is_sub setf width rd rn imm =>
      match getr s rn with
      | None => None
      | Some a =>
          let res := if is_sub then subm a imm width else addm a imm width in
          let c := N.leb imm (N.land a (mask_bits width)) in
          let z := N.eqb res 0 in
          let s1 := if setf && is_sub then setflags s c z next else setpc s next in
          setr s1 rd res
      end
  | Dup2d vd rn =>
      match getr s rn with
      | Some v =>
          if N.eqb vd 0 then Some (setdup s v next) else None
      | None => None
      end
  | StrQ vt rn off =>
      match getr s rn with
      | Some addr =>
          if negb (N.eqb vt 0) then None
          else
            match write_bytes s.(mem) (N.to_nat addr)
                    (le_bytes s.(lo) 8 ++ le_bytes s.(hi) 8) with
            | None => None
            | Some m =>
                match setr (setmem s m next true) rn (zadd addr off) with
                | None => None
                | Some s1 => Some (setpc s1 next)
                end
            end
      | None => None
      end
  | StpQ rt rt2 rn off =>
      match getr s rn with
      | Some addr =>
          if negb (N.eqb rt 0 && N.eqb rt2 0) then None
          else
            let bs := le_bytes s.(lo) 8 ++ le_bytes s.(hi) 8 in
            let a1 := zadd addr off in
            match write_bytes s.(mem) (N.to_nat a1) bs with
            | None => None
            | Some m1 =>
                match write_bytes m1 (N.to_nat (zadd a1 16%Z)) bs with
                | None => None
                | Some m2 => Some (setmem s m2 next true)
                end
            end
      | None => None
      end
  | StrPost nbytes rt rn imm =>
      match getr s rn, getr s rt with
      | Some addr, Some data =>
          match write_bytes s.(mem) (N.to_nat addr) (le_bytes data nbytes) with
          | None => None
          | Some m =>
              match setr (setmem s m next s.(qstore)) rn (zadd addr imm) with
              | None => None
              | Some s1 => Some (setpc s1 next)
              end
          end
      | _, _ => None
      end
  | StrB rt rn imm12 =>
      match getr s rn, getr s rt with
      | Some addr, Some data =>
          match write_bytes s.(mem) (N.to_nat (addr + imm12)) (le_bytes data 1) with
          | None => None
          | Some m => Some (setmem s m next s.(qstore))
          end
      | _, _ => None
      end
  | Tbz rt bit off =>
      match getr s rt with
      | None => None
      | Some v =>
          if N.testbit v bit then Some (setpc s next)
          else Some (setpc s (pc_add s.(pc) off))
      end
  | Bcond off cond =>
      match take_cond s.(fc) cond with
      | None => None
      | Some true => Some (setpc s (pc_add s.(pc) off))
      | Some false => Some (setpc s next)
      end
  | Cbz rt off =>
      match getr s rt with
      | None => None
      | Some v =>
          if N.eqb v 0 then Some (setpc s (pc_add s.(pc) off))
          else Some (setpc s next)
      end
  end.

Definition step_at (s : Mach) : option Mach :=
  match word_at s.(pc) with
  | None => None
  | Some w =>
      match decode w with
      | None => None
      | Some i => step s i
      end
  end.

(* Extra fuel after ret stays on the halted state. *)
Fixpoint steps (k : nat) (s : Mach) : option Mach :=
  match k with
  | O => Some s
  | S k =>
      if s.(done) then Some s
      else match step_at s with
           | None => None
           | Some s' => steps k s'
           end
  end.

Definition init (b n : nat) : Mach :=
  Mk 0 (N.of_nat b) (N.of_nat n) 0 0 0 0 (repeat 0 n) 0 false false false false.

Fixpoint bytes_eq (a b : list N) : bool :=
  match a, b with
  | [], [] => true
  | x :: a, y :: b => N.eqb x y && bytes_eq a b
  | _, _ => false
  end.
Lemma decode_code :
  map decode code =
  [ Some (Orr true 8 31 0 0)
  ; Some (And32 1 1 255)
  ; Some (Orr false 1 1 1 8)
  ; Some (Orr false 1 1 1 16)
  ; Some (Orr true 3 1 1 32)
  ; Some (Dup2d 0 3)
  ; Some (AddSub true true 64 31 2 16)
  ; Some (Bcond 35%Z 3)
  ; Some (AddSub true true 64 31 2 64)
  ; Some (Bcond 12%Z 3)
  ; Some Nop
  ; Some Nop
  ; Some (StpQ 0 0 0 0%Z)
  ; Some (StpQ 0 0 0 32%Z)
  ; Some (AddSub false false 64 0 0 64)
  ; Some (AddSub true false 64 2 2 64)
  ; Some (AddSub true true 64 31 2 64)
  ; Some (Bcond (-5)%Z 2)
  ; Some (Cbz 2 22%Z)
  ; Some (AddSub true true 64 31 2 16)
  ; Some (Bcond 6%Z 3)
  ; Some (StrQ 0 0 16%Z)
  ; Some (AddSub true false 64 2 2 16)
  ; Some (AddSub true true 64 31 2 16)
  ; Some (Bcond (-3)%Z 2)
  ; Some (Cbz 2 15%Z)
  ; Some (AddSub true true 64 31 2 8)
  ; Some (Bcond 3%Z 3)
  ; Some (StrPost 8%nat 3 0 8%Z)
  ; Some (AddSub true false 64 2 2 8)
  ; Some (AddSub true true 64 31 2 4)
  ; Some (Bcond 3%Z 3)
  ; Some (StrPost 4%nat 3 0 4%Z)
  ; Some (AddSub true false 64 2 2 4)
  ; Some (AddSub true true 64 31 2 2)
  ; Some (Bcond 3%Z 3)
  ; Some (StrPost 2%nat 3 0 2%Z)
  ; Some (AddSub true false 64 2 2 2)
  ; Some (Cbz 2 2%Z)
  ; Some (StrB 3 0 0)
  ; Some (Orr true 0 31 8 0)
  ; Some Ret
  ; Some (Tbz 2 3 3%Z)
  ; Some (StrPost 8%nat 3 0 8%Z)
  ; Some (AddSub true false 64 2 2 8)
  ; Some (Tbz 2 2 3%Z)
  ; Some (StrPost 4%nat 3 0 4%Z)
  ; Some (AddSub true false 64 2 2 4)
  ; Some (Tbz 2 1 3%Z)
  ; Some (StrPost 2%nat 3 0 2%Z)
  ; Some (AddSub true false 64 2 2 2)
  ; Some (Tbz 2 0 (-11)%Z)
  ; Some (StrB 3 0 0)
  ; Some (B (-13)%Z)
  ; Some Nop
  ; Some Nop
  ].
Proof. vm_compute. reflexivity. Qed.
Lemma mask64_ones : mask_bits 64 = N.ones 64.
Proof. vm_compute. reflexivity. Qed.

Lemma of_nat_lt_mono : forall n m,
  (n < m)%nat -> N.of_nat n < N.of_nat m.
Proof.
  intros n m H.
  apply (proj1 (N.compare_lt_iff (N.of_nat n) (N.of_nat m))).
  rewrite <- Nat2N.inj_compare.
  destruct (Nat.compare_spec n m) as [E|L|G].
  - lia.
  - reflexivity.
  - lia.
Qed.

Lemma of_nat_le_mono : forall n m,
  (n <= m)%nat -> N.of_nat n <= N.of_nat m.
Proof.
  intros n m H.
  apply N.lt_eq_cases.
  destruct (Nat.eq_dec n m) as [->|Hne].
  - right. reflexivity.
  - left. apply of_nat_lt_mono. lia.
Qed.

Lemma pow64N : N.of_nat (2 ^ 64) = 2 ^ 64.
Proof. rewrite (Nat2N.inj_pow 2 64). reflexivity. Qed.

Lemma below64 : forall n,
  (n < 2 ^ 64)%nat -> N.of_nat n < 2 ^ 64.
Proof.
  intros n H. rewrite <- pow64N. apply of_nat_lt_mono. exact H.
Qed.

Lemma land64_id : forall n,
  (n < 2 ^ 64)%nat ->
  N.land (N.of_nat n) (mask_bits 64) = N.of_nat n.
Proof.
  intros n Hn.
  rewrite mask64_ones, N.land_ones.
  apply N.mod_small. apply below64. exact Hn.
Qed.

Lemma leb_nat : forall a b,
  N.leb (N.of_nat a) (N.of_nat b) = (a <=? b)%nat.
Proof.
  intros a b.
  destruct (Nat.leb_spec a b) as [Hab|Hab].
  - apply N.leb_le. apply of_nat_le_mono. exact Hab.
  - apply N.leb_gt. apply of_nat_lt_mono. exact Hab.
Qed.

Lemma eqb_nat : forall a b,
  (N.eqb (N.of_nat a) (N.of_nat b) = (a =? b)%nat).
Proof.
  intros a b.
  destruct (Nat.eq_dec a b) as [->|Hne].
  - rewrite Nat.eqb_refl. apply N.eqb_refl.
  - rewrite (proj2 (Nat.eqb_neq a b) Hne).
    apply N.eqb_neq. intro E. apply Nat2N.inj in E. contradiction.
Qed.

Lemma addm_small : forall a i,
  (a + i < 2 ^ 64)%nat ->
  addm (N.of_nat a) (N.of_nat i) 64 = N.of_nat (a + i).
Proof.
  intros a i H.
  unfold addm.
  rewrite !land64_id by lia.
  rewrite mask64_ones, N.land_ones, <- Nat2N.inj_add.
  apply N.mod_small. apply below64. lia.
Qed.

Lemma ones_pred : N.ones 64 = N.pred (2 ^ 64).
Proof.
  rewrite <- mask64_ones. unfold mask_bits.
  rewrite N.shiftl_mul_pow2.
  replace (1 * 2 ^ 64) with (2 ^ 64) by lia.
  reflexivity.
Qed.

Lemma pred_plus1 : N.pred (2 ^ 64) + 1 = 2 ^ 64.
Proof.
  rewrite <- (N.succ_pred (2 ^ 64)).
  - reflexivity.
  - discriminate.
Qed.

Lemma sub_succ_r : forall m i,
  i <= m -> m - i + 1 = m + 1 - i.
Proof.
  intros m i Hi. lia.
Qed.

Lemma subm_shift : forall i,
  (i < 2 ^ 64)%nat ->
  N.pred (2 ^ 64) - N.of_nat i + 1 = 2 ^ 64 - N.of_nat i.
Proof.
  intros i Hi.
  rewrite sub_succ_r.
  - rewrite pred_plus1. reflexivity.
  - apply N.lt_succ_r. rewrite N.succ_pred by discriminate.
    apply below64. exact Hi.
Qed.

Lemma subm_ge : forall a i,
  (i <= a)%nat ->
  (a < 2 ^ 64)%nat ->
  subm (N.of_nat a) (N.of_nat i) 64 = N.of_nat (a - i).
Proof.
  intros a i Hi Ha.
  unfold subm.
  rewrite !land64_id by lia.
  rewrite !mask64_ones.
  rewrite <- N.add_assoc.
  replace (N.ones 64 - N.of_nat i + 1) with (2 ^ 64 - N.of_nat i).
  2: { rewrite ones_pred. symmetry. apply subm_shift. lia. }
  assert (Hsum : N.of_nat a + (2 ^ 64 - N.of_nat i) =
                  N.of_nat (a - i) + 2 ^ 64).
  { rewrite <- pow64N.
    rewrite <- (Nat2N.inj_sub (2 ^ 64) i) by lia.
    rewrite <- !Nat2N.inj_add.
    f_equal. lia. }
  rewrite Hsum, N.land_ones.
  replace (2 ^ 64) with (1 * 2 ^ 64) by lia.
  rewrite N.Div0.mod_add.
  apply N.mod_small. apply below64. lia.
Qed.

Lemma wrap_eq : forall a i,
  (a < i < 2 ^ 64)%nat ->
  N.of_nat a + (2 ^ 64 - N.of_nat i) = 2 ^ 64 - N.of_nat (i - a).
Proof.
  intros a i [Ha Hi].
  rewrite <- pow64N.
  rewrite <- (Nat2N.inj_sub (2 ^ 64) i) by lia.
  rewrite <- Nat2N.inj_add.
  rewrite <- (Nat2N.inj_sub (2 ^ 64) (i - a)) by lia.
  f_equal. lia.
Qed.

Lemma sub_pos_lt : forall x,
  (0 < x)%nat ->
  (x < 2 ^ 64)%nat ->
  2 ^ 64 - N.of_nat x < 2 ^ 64.
Proof.
  intros x Hx Hx64.
  rewrite <- pow64N.
  rewrite <- (Nat2N.inj_sub (2 ^ 64) x) by lia.
  apply of_nat_lt_mono. lia.
Qed.

Lemma subm_lt : forall a i,
  (a < i)%nat ->
  (i < 2 ^ 64)%nat ->
  subm (N.of_nat a) (N.of_nat i) 64 = 2 ^ 64 - N.of_nat (i - a).
Proof.
  intros a i Ha Hi.
  unfold subm.
  rewrite !land64_id by lia.
  rewrite !mask64_ones.
  rewrite <- N.add_assoc.
  replace (N.ones 64 - N.of_nat i + 1) with (2 ^ 64 - N.of_nat i).
  2: { rewrite ones_pred. symmetry. apply subm_shift. lia. }
  rewrite wrap_eq by lia.
  rewrite N.land_ones.
  apply N.mod_small.
  apply sub_pos_lt; lia.
Qed.

Lemma flag_Z : forall rest imm,
  (rest < 2 ^ 64)%nat ->
  (imm < 2 ^ 64)%nat ->
  N.eqb (subm (N.of_nat rest) (N.of_nat imm) 64) 0 = (rest =? imm)%nat.
Proof.
  intros rest imm Hr Hi.
  destruct (Nat.lt_trichotomy rest imm) as [Hlt|[Heq|Hgt]].
  - rewrite subm_lt by lia.
    rewrite (proj2 (Nat.eqb_neq rest imm)) by lia.
    apply N.eqb_neq. intro E.
    assert (Hxle : N.of_nat (imm - rest) <= 2 ^ 64).
    { apply N.lt_le_incl. apply below64. lia. }
    assert (2 ^ 64 = N.of_nat (imm - rest)).
    { rewrite <- (N.sub_add (N.of_nat (imm - rest)) (2 ^ 64)) by exact Hxle.
      rewrite E. apply N.add_0_l. }
    apply (f_equal N.to_nat) in H.
    rewrite <- pow64N in H.
    rewrite !Nat2N.id in H.
    lia.
  - subst imm.
    rewrite subm_ge by lia.
    replace (rest - rest)%nat with 0%nat by lia.
    rewrite Nat.eqb_refl. reflexivity.
  - rewrite subm_ge by lia.
    change 0 with (N.of_nat 0).
    rewrite eqb_nat.
    rewrite (proj2 (Nat.eqb_neq (rest - imm) 0)) by lia.
    rewrite (proj2 (Nat.eqb_neq rest imm)) by lia.
    reflexivity.
Qed.

Lemma flag_C : forall rest imm,
  (rest < 2 ^ 64)%nat ->
  (imm < 2 ^ 64)%nat ->
  N.leb (N.of_nat imm) (N.land (N.of_nat rest) (mask_bits 64)) = (imm <=? rest)%nat.
Proof.
  intros rest imm Hr Hi.
  rewrite land64_id by exact Hr.
  apply leb_nat.
Qed.

Lemma zadd_nat : forall base off,
  zadd (N.of_nat base) (Z.of_nat off) = N.of_nat (base + off).
Proof.
  intros base off.
  unfold zadd.
  rewrite nat_N_Z.
  rewrite <- Nat2Z.inj_add.
  rewrite <- nat_N_Z.
  apply N2Z.id.
Qed.

Lemma bytes_eq_spec : forall a b, bytes_eq a b = true -> a = b.
Proof.
  induction a as [|x a IH]; intros [|y b] H; simpl in H; try discriminate.
  - reflexivity.
  - apply andb_true_iff in H. destruct H as [Hx Ht].
    apply N.eqb_eq in Hx. subst y. f_equal. apply IH. exact Ht.
Qed.

Lemma forallb_seq_from :
  forall (f : nat -> bool) start len i,
    forallb f (seq start len) = true ->
    (start <= i < start + len)%nat ->
    f i = true.
Proof.
  intros f start len. revert start.
  induction len as [|len IH]; intros start i Hall Hrange.
  - lia.
  - simpl in Hall.
    apply andb_true_iff in Hall. destruct Hall as [Hf Htail].
    destruct (Nat.eq_dec i start) as [->|Hne].
    + exact Hf.
    + apply (IH (S start) i Htail). lia.
Qed.

Lemma repeat_add : forall (A : Type) (x : A) n m,
  repeat x n ++ repeat x m = repeat x (n + m)%nat.
Proof.
  intros A x n m. induction n as [|n IH]; simpl; [reflexivity|].
  f_equal. exact IH.
Qed.

Lemma firstn_repeat : forall (A : Type) (x : A) n k,
  (k <= n)%nat -> firstn k (repeat x n) = repeat x k.
Proof.
  intros A x n k. revert n.
  induction k as [|k IH]; intros n Hk; simpl.
  - reflexivity.
  - destruct n as [|n]; [lia|]. simpl. f_equal. apply IH. lia.
Qed.

Lemma le_bytes_firstn : forall w n k,
  (k <= n)%nat -> firstn k (le_bytes w n) = le_bytes w k.
Proof.
  intros w n k. revert w n.
  induction k as [|k IH]; intros w n Hk.
  - reflexivity.
  - destruct n as [|n]; [lia|]. simpl. f_equal. apply IH. lia.
Qed.

Lemma write1_at : forall (b : N) (filled rest : nat),
  write1 (repeat b filled ++ repeat 0 (S rest)) filled b
  = Some (repeat b (S filled) ++ repeat 0 rest).
Proof.
  intros b filled. induction filled as [|filled IH]; intros rest.
  - simpl. reflexivity.
  - change (repeat b (S filled)) with (b :: repeat b filled) at 1.
    cbn [app write1].
    rewrite IH. cbn. reflexivity.
Qed.

Lemma write_block : forall k (b : N) filled rest,
  (k <= rest)%nat ->
  write_bytes (repeat b filled ++ repeat 0 rest) filled (repeat b k)
  = Some (repeat b (filled + k) ++ repeat 0 (rest - k)).
Proof.
  induction k as [|k IH]; intros b filled rest Hk.
  - simpl. rewrite Nat.add_0_r, Nat.sub_0_r. reflexivity.
  - destruct rest as [|rest']; [lia|].
    change (repeat b (S k)) with (b :: repeat b k).
    cbn [write_bytes].
    rewrite write1_at.
    rewrite (IH b (S filled) rest') by lia.
    replace (S filled + k)%nat with (filled + S k)%nat by lia.
    replace (rest' - k)%nat with (S rest' - S k)%nat by lia.
    reflexivity.
Qed.

Definition byte8 (bn : nat) : bool :=
  bytes_eq (le_bytes (N.of_nat bn * 0x0101010101010101) 8)
           (repeat (N.of_nat bn) 8).

Lemma le8_table : forallb byte8 (seq 0 256)%nat = true.
Proof. vm_compute. reflexivity. Qed.

Lemma le_bytes_8 : forall bn,
  (bn < 256)%nat ->
  le_bytes (N.of_nat bn * 0x0101010101010101) 8 = repeat (N.of_nat bn) 8.
Proof.
  intros bn Hbn.
  apply bytes_eq_spec.
  change (byte8 bn = true).
  apply (forallb_seq_from byte8 0%nat 256%nat bn).
  - exact le8_table.
  - lia.
Qed.

Definition splatb (b : N) : N := b * 0x0101010101010101.
Definition lowb (b : N) : N := b * 0x01010101.

Lemma to_nat_below : forall a n,
  a < N.of_nat n -> (N.to_nat a < n)%nat.
Proof.
  intros a n H.
  destruct (Nat.lt_ge_cases (N.to_nat a) n) as [Hlt|Hge]; [exact Hlt|].
  exfalso.
  apply (N.lt_irrefl a).
  apply N.lt_le_trans with (N.of_nat n).
  - exact H.
  - rewrite <- (N2Nat.id a). apply of_nat_le_mono. exact Hge.
Qed.

Lemma le_bytes_splat8 : forall b,
  b < 256 -> le_bytes (splatb b) 8 = repeat b 8.
Proof.
  intros b Hb.
  rewrite <- (N2Nat.id b). unfold splatb.
  apply le_bytes_8.
  apply to_nat_below.
  exact Hb.
Qed.

Lemma le_bytes_width : forall b k,
  b < 256 -> (k <= 8)%nat ->
  le_bytes (splatb b) k = repeat b k.
Proof.
  intros b k Hb Hk.
  rewrite <- (le_bytes_firstn (splatb b) 8 k Hk).
  rewrite le_bytes_splat8 by exact Hb.
  apply firstn_repeat. exact Hk.
Qed.

Definition byte_check (bn : nat) : bool :=
  let a := N.of_nat bn in
  let a1 := orrv a a 8 32 in
  let a2 := orrv a1 a1 16 32 in
  let a3 := orrv a2 a2 32 64 in
  N.eqb a1 (a * 0x101) && N.eqb a2 (a * 0x01010101) &&
  N.eqb a3 (a * 0x0101010101010101) &&
  N.eqb (N.land (N.land a (mask_bits 32)) 255) a.

Lemma chain_table : forallb byte_check (seq 0 256)%nat = true.
Proof. vm_compute. reflexivity. Qed.

Lemma chain_byte : forall bn,
  (bn < 256)%nat ->
  let a := N.of_nat bn in
  orrv a a 8 32 = a * 0x101 /\
  orrv (a * 0x101) (a * 0x101) 16 32 = a * 0x01010101 /\
  orrv (a * 0x01010101) (a * 0x01010101) 32 64 =
    a * 0x0101010101010101 /\
  N.land (N.land a (mask_bits 32)) 255 = a.
Proof.
  intros bn Hbn.
  assert (Hcheck : byte_check bn = true).
  { apply (forallb_seq_from byte_check 0%nat 256%nat bn).
    - exact chain_table.
    - lia. }
  unfold byte_check in Hcheck. cbn zeta in Hcheck.
  apply andb_true_iff in Hcheck. destruct Hcheck as [Hcheck H4].
  apply andb_true_iff in Hcheck. destruct Hcheck as [Hcheck H3].
  apply andb_true_iff in Hcheck. destruct Hcheck as [H1 H2].
  apply N.eqb_eq in H1, H2, H3, H4.
  rewrite H1 in H2, H3. rewrite H2 in H3.
  cbn zeta. repeat split; exact H1 || exact H2 || exact H3 || exact H4.
Qed.

Lemma bit_table :
  forallb (fun n =>
    Bool.eqb (N.testbit (N.of_nat n) 3) ((8 <=? n)%nat) &&
    Bool.eqb (N.testbit (N.of_nat n) 2) ((4 <=? Nat.modulo n 8)%nat) &&
    Bool.eqb (N.testbit (N.of_nat n) 1) ((2 <=? Nat.modulo n 4)%nat) &&
    Bool.eqb (N.testbit (N.of_nat n) 0) (Nat.odd n))
    (seq 0 16)%nat = true.
Proof. vm_compute. reflexivity. Qed.

Lemma steps_one : forall s s',
  s.(done) = false -> step_at s = Some s' -> steps 1%nat s = Some s'.
Proof. intros s s' Hd Hs. simpl. rewrite Hd, Hs. reflexivity. Qed.

Lemma steps_seq : forall k1 k2 s s1 s2,
  steps k1 s = Some s1 ->
  s1.(done) = false ->
  steps k2 s1 = Some s2 ->
  steps (k1 + k2)%nat s = Some s2.
Proof.
  induction k1 as [|k1 IH]; intros k2 s s1 s2 H1 Hd H2.
  - simpl in H1. inversion H1. subst s1. exact H2.
  - simpl in H1. destruct (done s) eqn:Hdone.
    + inversion H1. subst s1. congruence.
    + destruct (step_at s) as [s'|] eqn:Hs; [|discriminate].
      simpl. rewrite Hdone. rewrite Hs. eapply IH; eauto.
Qed.

Ltac red_at p :=
  match eval vm_compute in (word_at p) with
  | Some ?word =>
      replace (word_at p) with (Some word) by (vm_compute; reflexivity);
      match eval vm_compute in (decode word) with
      | ?ins => replace (decode word) with ins by (vm_compute; reflexivity)
      end
  end.

Lemma mov_step : forall b n,
  step_at (init b n) =
  Some (Mk 0 (N.of_nat b) (N.of_nat n) 0 0 0 0 (repeat 0 n) 4 false false false false).
Proof.
  intros b n.
  unfold step_at. red_at 0. unfold step.
  cbn [getr setr setpc].
  replace (orrv 0 0 0 64) with 0 by (vm_compute; reflexivity).
  reflexivity.
Qed.
