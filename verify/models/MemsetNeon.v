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
(* --- any length: one-step facts --- *)

Lemma eqb0_nat : forall n, N.eqb (N.of_nat n) 0 = (n =? 0)%nat.
Proof. intros n. change 0 with (N.of_nat 0). apply eqb_nat. Qed.

Lemma of_nat_byte : forall bn, (bn < 256)%nat -> N.of_nat bn < 256.
Proof. intros bn H. apply of_nat_lt_mono in H. exact H. Qed.

Lemma zadd_0 : forall a, zadd a 0%Z = a.
Proof. intros a. unfold zadd. rewrite Z.add_0_r. apply N2Z.id. Qed.

Lemma zadd16 : forall base,
  zadd (N.of_nat base) 16%Z = N.of_nat (base + 16).
Proof. intros base. rewrite <- (zadd_nat base 16). reflexivity. Qed.

Lemma zadd32 : forall base,
  zadd (N.of_nat base) 32%Z = N.of_nat (base + 32).
Proof. intros base. rewrite <- (zadd_nat base 32). reflexivity. Qed.

Lemma zadd8 : forall base,
  zadd (N.of_nat base) 8%Z = N.of_nat (base + 8).
Proof. intros base. rewrite <- (zadd_nat base 8). reflexivity. Qed.

Lemma zadd4 : forall base,
  zadd (N.of_nat base) 4%Z = N.of_nat (base + 4).
Proof. intros base. rewrite <- (zadd_nat base 4). reflexivity. Qed.

Lemma zadd2 : forall base,
  zadd (N.of_nat base) 2%Z = N.of_nat (base + 2).
Proof. intros base. rewrite <- (zadd_nat base 2). reflexivity. Qed.

Lemma le_bytes_16 : forall b,
  b < 256 ->
  le_bytes (splatb b) 8 ++ le_bytes (splatb b) 8 = repeat b 16.
Proof.
  intros b Hb.
  rewrite !le_bytes_splat8 by exact Hb.
  rewrite repeat_add. reflexivity.
Qed.

Definition canon (bn : N) (filled rest : nat) (p : N) (c z qs : bool) : Mach :=
  Mk (N.of_nat filled) (lowb bn) (N.of_nat rest) (splatb bn) 0
     (splatb bn) (splatb bn)
     (repeat bn filled ++ repeat 0 rest)
     p c z false qs.

Lemma canon_done : forall bn filled rest p c z qs,
  (canon bn filled rest p c z qs).(done) = false.
Proof. reflexivity. Qed.

(* stp q0, q0, [x0] at pc 48: 32 bytes, pointer stays. *)
Lemma stp48 : forall b filled rest c z qs,
  b < 256 ->
  (32 <= rest)%nat ->
  step_at (canon b filled rest 48 c z qs) =
  Some (Mk (N.of_nat filled) (lowb b) (N.of_nat rest) (splatb b) 0
           (splatb b) (splatb b)
           (repeat b (filled + 32) ++ repeat 0 (rest - 32))
           52 c z false true).
Proof.
  intros b filled rest c z qs Hb Hrest.
  unfold canon, step_at.
  cbn [pc].
  red_at 48.
  cbn iota beta.
  unfold step.
  cbn [getr lo hi mem r0 pc N.eqb andb negb].
  rewrite zadd_0. rewrite Nat2N.id.
  replace (le_bytes (splatb b) 8 ++ le_bytes (splatb b) 8) with (repeat b 16)
    by (symmetry; apply le_bytes_16; exact Hb).
  assert (H16 : (16 <= rest)%nat) by lia.
  rewrite (write_block 16 b filled rest H16).
  cbn iota.
  rewrite zadd16.
  rewrite Nat2N.id.
  rewrite (write_block 16 b (filled + 16) (rest - 16)) by lia.
  cbn iota.
  cbn [setmem].
  replace (filled + 16 + 16)%nat with (filled + 32)%nat by lia.
  replace (rest - 16 - 16)%nat with (rest - 32)%nat by lia.
  reflexivity.
Qed.
(* --- one machine step, instruction supplied by the caller --- *)

Lemma step_then : forall s s' k s2,
  s.(done) = false ->
  step_at s = Some s' ->
  steps k s' = Some s2 ->
  steps (S k) s = Some s2.
Proof. intros s s' k s2 Hd Hs Hk. simpl. rewrite Hd, Hs. exact Hk. Qed.

Lemma step_cmp : forall r0 r1 r3 r8 lo hi mem p c z qs rest imm w,
  (rest < 2 ^ 64)%nat ->
  (imm < 2 ^ 64)%nat ->
  word_at p = Some w ->
  decode w = Some (AddSub true true 64 31 2 (N.of_nat imm)) ->
  step_at (Mk r0 r1 (N.of_nat rest) r3 r8 lo hi mem p c z false qs) =
  Some (Mk r0 r1 (N.of_nat rest) r3 r8 lo hi mem (p + 4)
           ((imm <=? rest)%nat) ((rest =? imm)%nat) false qs).
Proof.
  intros.
  unfold step_at. cbn [pc]. rewrite H1, H2. unfold step.
  cbn [getr setr setflags setpc andb r2].
  rewrite flag_C by lia. rewrite flag_Z by lia. reflexivity.
Qed.

Lemma step_add0 : forall r1 r2 r3 r8 lo hi mem p c z qs filled delta w,
  (filled + delta < 2 ^ 64)%nat ->
  word_at p = Some w ->
  decode w = Some (AddSub false false 64 0 0 (N.of_nat delta)) ->
  step_at (Mk (N.of_nat filled) r1 r2 r3 r8 lo hi mem p c z false qs) =
  Some (Mk (N.of_nat (filled + delta)) r1 r2 r3 r8 lo hi mem (p + 4) c z false qs).
Proof.
  intros.
  unfold step_at. cbn [pc]. rewrite H0, H1. unfold step.
  cbn [getr setr setpc andb r0].
  rewrite addm_small by lia. rewrite Nat2N.inj_add. reflexivity.
Qed.

Lemma step_sub2 : forall r0 r1 r3 r8 lo hi mem p c z qs rest delta w,
  (delta <= rest)%nat ->
  (rest < 2 ^ 64)%nat ->
  word_at p = Some w ->
  decode w = Some (AddSub true false 64 2 2 (N.of_nat delta)) ->
  step_at (Mk r0 r1 (N.of_nat rest) r3 r8 lo hi mem p c z false qs) =
  Some (Mk r0 r1 (N.of_nat (rest - delta)) r3 r8 lo hi mem (p + 4) c z false qs).
Proof.
  intros.
  unfold step_at. cbn [pc]. rewrite H1, H2. unfold step.
  cbn [getr setr setpc andb r2].
  rewrite subm_ge by lia. reflexivity.
Qed.

Lemma step_bcond : forall r0 r1 r2 r3 r8 lo hi mem p c z qs off cond taken w,
  word_at p = Some w ->
  decode w = Some (Bcond off cond) ->
  take_cond c cond = Some taken ->
  step_at (Mk r0 r1 r2 r3 r8 lo hi mem p c z false qs) =
  Some (Mk r0 r1 r2 r3 r8 lo hi mem
            (if taken then pc_add p off else p + 4) c z false qs).
Proof.
  intros.
  unfold step_at. cbn [pc]. rewrite H, H0. unfold step. cbn [fc]. rewrite H1.
  destruct taken; cbn [setpc]; reflexivity.
Qed.

Lemma step_cbz : forall r0 r1 r3 r8 lo hi mem p c z qs rest off w,
  word_at p = Some w ->
  decode w = Some (Cbz 2 off) ->
  step_at (Mk r0 r1 (N.of_nat rest) r3 r8 lo hi mem p c z false qs) =
  Some (Mk r0 r1 (N.of_nat rest) r3 r8 lo hi mem
            (if (rest =? 0)%nat then pc_add p off else p + 4) c z false qs).
Proof.
  intros.
  unfold step_at. cbn [pc]. rewrite H, H0. unfold step.
  cbn [getr setpc r2]. rewrite eqb0_nat.
  destruct (rest =? 0)%nat; reflexivity.
Qed.

Lemma step_tbz : forall r0 r1 r3 r8 lo hi mem p c z qs rest bit off w,
  word_at p = Some w ->
  decode w = Some (Tbz 2 bit off) ->
  step_at (Mk r0 r1 (N.of_nat rest) r3 r8 lo hi mem p c z false qs) =
  Some (Mk r0 r1 (N.of_nat rest) r3 r8 lo hi mem
            (if N.testbit (N.of_nat rest) bit then p + 4 else pc_add p off)
            c z false qs).
Proof.
  intros.
  unfold step_at. cbn [pc]. rewrite H, H0. unfold step.
  cbn [getr setpc r2]. destruct (N.testbit (N.of_nat rest) bit); reflexivity.
Qed.

Lemma step_b : forall r0 r1 r2 r3 r8 lo hi mem p c z qs off w,
  word_at p = Some w ->
  decode w = Some (B off) ->
  step_at (Mk r0 r1 r2 r3 r8 lo hi mem p c z false qs) =
  Some (Mk r0 r1 r2 r3 r8 lo hi mem (pc_add p off) c z false qs).
Proof.
  intros. unfold step_at. cbn [pc]. rewrite H, H0. unfold step. cbn [setpc]. reflexivity.
Qed.

Lemma step_nop : forall r0 r1 r2 r3 r8 lo hi mem p c z qs w,
  word_at p = Some w ->
  decode w = Some Nop ->
  step_at (Mk r0 r1 r2 r3 r8 lo hi mem p c z false qs) =
  Some (Mk r0 r1 r2 r3 r8 lo hi mem (p + 4) c z false qs).
Proof.
  intros. unfold step_at. cbn [pc]. rewrite H, H0. unfold step. cbn [setpc]. reflexivity.
Qed.

Lemma step_ret : forall r0 r1 r2 r3 r8 lo hi mem p c z qs w,
  word_at p = Some w ->
  decode w = Some Ret ->
  step_at (Mk r0 r1 r2 r3 r8 lo hi mem p c z false qs) =
  Some (Mk r0 r1 r2 r3 r8 lo hi mem p c z true qs).
Proof. intros. unfold step_at. cbn [pc]. rewrite H, H0. reflexivity. Qed.

Lemma step_mov0 : forall r0 r1 r2 r3 lo hi mem p c z qs w,
  word_at p = Some w ->
  decode w = Some (Orr true 0 31 8 0) ->
  step_at (Mk r0 r1 r2 r3 0 lo hi mem p c z false qs) =
  Some (Mk 0 r1 r2 r3 0 lo hi mem (p + 4) c z false qs).
Proof.
  intros.
  unfold step_at. cbn [pc]. rewrite H, H0. unfold step.
  cbn [getr setr setpc r8].
  replace (orrv 0 0 0 64) with 0 by (vm_compute; reflexivity).
  reflexivity.
Qed.

(* 32-byte stp of the splat, pointer unchanged, qstore set. *)
Lemma step_stp : forall b ptr delta rest r1 r2 r3 r8 p c z qs w,
  b < 256 ->
  (32 <= rest)%nat ->
  word_at p = Some w ->
  decode w = Some (StpQ 0 0 0 (Z.of_nat delta)) ->
  step_at (Mk (N.of_nat ptr) r1 r2 r3 r8 (splatb b) (splatb b)
              (repeat b (ptr + delta) ++ repeat 0 rest)
              p c z false qs) =
  Some (Mk (N.of_nat ptr) r1 r2 r3 r8 (splatb b) (splatb b)
            (repeat b (ptr + delta + 32) ++ repeat 0 (rest - 32))
            (p + 4) c z false true).
Proof.
  intros b ptr delta rest r1 r2 r3 r8 p c z qs w Hb Hrest Hw Hd.
  unfold step_at. cbn [pc]. rewrite Hw, Hd. unfold step.
  cbn [getr lo hi mem r0 pc N.eqb andb negb].
  rewrite zadd_nat. rewrite Nat2N.id.
  replace (le_bytes (splatb b) 8 ++ le_bytes (splatb b) 8) with (repeat b 16)
    by (symmetry; apply le_bytes_16; exact Hb).
  assert (H16 : (16 <= rest)%nat) by lia.
  rewrite (write_block 16 b (ptr + delta) rest H16).
  cbn iota.
  rewrite zadd16. rewrite Nat2N.id.
  rewrite (write_block 16 b (ptr + delta + 16) (rest - 16)) by lia.
  cbn iota. cbn [setmem].
  replace (ptr + delta + 16 + 16)%nat with (ptr + delta + 32)%nat by lia.
  replace (rest - 16 - 16)%nat with (rest - 32)%nat by lia.
  reflexivity.
Qed.

Lemma step_strq : forall b ptr rest r1 r2 r8 p c z qs w,
  b < 256 ->
  (16 <= rest)%nat ->
  word_at p = Some w ->
  decode w = Some (StrQ 0 0 16%Z) ->
  step_at (Mk (N.of_nat ptr) r1 r2 (splatb b) r8 (splatb b) (splatb b)
              (repeat b ptr ++ repeat 0 rest) p c z false qs) =
  Some (Mk (N.of_nat (ptr + 16)) r1 r2 (splatb b) r8 (splatb b) (splatb b)
            (repeat b (ptr + 16) ++ repeat 0 (rest - 16))
            (p + 4) c z false true).
Proof.
  intros b ptr rest r1 r2 r8 p c z qs w Hb Hrest Hw Hd.
  unfold step_at. cbn [pc]. rewrite Hw, Hd. unfold step.
  cbn [getr lo hi mem r0 pc N.eqb negb].
  rewrite Nat2N.id.
  replace (le_bytes (splatb b) 8 ++ le_bytes (splatb b) 8) with (repeat b 16)
    by (symmetry; apply le_bytes_16; exact Hb).
  rewrite (write_block 16 b ptr rest Hrest).
  cbn iota.
  rewrite zadd16.
  cbn [setr setmem setpc].
  reflexivity.
Qed.

Lemma step_strk : forall b ptr rest k r1 r8 p c z qs w,
  b < 256 ->
  (k <= rest)%nat ->
  (k <= 8)%nat ->
  word_at p = Some w ->
  decode w = Some (StrPost k 3 0 (Z.of_nat k)) ->
  step_at (Mk (N.of_nat ptr) r1 (N.of_nat rest) (splatb b) r8
              (splatb b) (splatb b)
              (repeat b ptr ++ repeat 0 rest) p c z false qs) =
  Some (Mk (N.of_nat (ptr + k)) r1 (N.of_nat rest) (splatb b) r8
            (splatb b) (splatb b)
            (repeat b (ptr + k) ++ repeat 0 (rest - k))
            (p + 4) c z false qs).
Proof.
  intros b ptr rest k r1 r8 p c z qs w Hb Hk H8 Hw Hd.
  unfold step_at. cbn [pc]. rewrite Hw, Hd. unfold step.
  cbn [getr lo hi mem r0 r3 pc].
  rewrite zadd_nat. rewrite Nat2N.id.
  rewrite le_bytes_width by (exact Hb || lia).
  rewrite (write_block k b ptr rest Hk).
  cbn iota.
  cbn [setr setmem setpc].
  rewrite Nat2N.inj_add. reflexivity.
Qed.

Lemma step_strb : forall b ptr rest r1 r2 r8 p c z qs w,
  b < 256 ->
  (1 <= rest)%nat ->
  word_at p = Some w ->
  decode w = Some (StrB 3 0 0) ->
  step_at (Mk (N.of_nat ptr) r1 r2 (splatb b) r8 (splatb b) (splatb b)
              (repeat b ptr ++ repeat 0 rest) p c z false qs) =
  Some (Mk (N.of_nat ptr) r1 r2 (splatb b) r8 (splatb b) (splatb b)
            (repeat b (ptr + 1) ++ repeat 0 (rest - 1))
            (p + 4) c z false qs).
Proof.
  intros b ptr rest r1 r2 r8 p c z qs w Hb Hone Hw Hd.
  unfold step_at. cbn [pc]. rewrite Hw, Hd. unfold step.
  cbn [getr lo hi mem r0 r3 pc].
  rewrite N.add_0_r. rewrite Nat2N.id.
  rewrite (le_bytes_width b 1%nat) by (exact Hb || lia).
  rewrite (write_block 1%nat b ptr rest) by lia.
  cbn [setmem].
  reflexivity.
Qed.

(* Closed word/decode pairs used by the control-flow proof. *)
Lemma W_add64 : word_at 56 = Some 0x91010000 /\
  decode 0x91010000 = Some (AddSub false false 64 0 0 (N.of_nat 64)).
Proof. vm_compute. split; reflexivity. Qed.

Lemma use_add56 : forall r1 r2 r3 r8 lo hi mem c z qs filled,
  (filled + 64 < 2 ^ 64)%nat ->
  step_at (Mk (N.of_nat filled) r1 r2 r3 r8 lo hi mem 56 c z false qs) =
  Some (Mk (N.of_nat (filled + 64)) r1 r2 r3 r8 lo hi mem 60 c z false qs).
Proof.
  intros r1 r2 r3 r8 lo hi mem c z qs filled H.
  destruct W_add64 as [Hw Hd].
  etransitivity.
  - apply (step_add0 r1 r2 r3 r8 lo hi mem 56 c z qs filled 64%nat
            0x91010000 H Hw Hd).
  - reflexivity.
Qed.
Ltac take_word p ins :=
  let w := eval vm_compute in
    (match word_at p with Some w0 => w0 | None => 0 end) in
  let H := fresh "Hw" in
  let Hw := fresh "Hword" in
  let Hd := fresh "Hdec" in
  assert (H : word_at p = Some w /\ decode w = Some ins)
    by (vm_compute; split; reflexivity);
  destruct H as [Hw Hd].

Lemma epilogue : forall r0 r1 r2 r3 lo hi mem c z qs,
  steps 2%nat (Mk r0 r1 r2 r3 0 lo hi mem 160 c z false qs) =
  Some (Mk 0 r1 r2 r3 0 lo hi mem 164 c z true qs).
Proof.
  intros r0 r1 r2 r3 lo hi mem c z qs.
  take_word 160 (Orr true 0 31 8 0).
  take_word 164 Ret.
  apply step_then with
    (s' := Mk 0 r1 r2 r3 0 lo hi mem (160 + 4) c z false qs).
  - reflexivity.
  - eapply step_mov0; [exact Hword | exact Hdec].
  - apply step_then with
      (s' := Mk 0 r1 r2 r3 0 lo hi mem (160 + 4) c z true qs).
    + reflexivity.
    + eapply step_ret; [exact Hword0 | exact Hdec0].
    + replace (160 + 4) with 164 by reflexivity. reflexivity.
Qed.
Ltac word_pair p ins k :=
  let w := eval vm_compute in
    (match word_at p with Some w0 => w0 | None => 0 end) in
  let H1 := fresh "Hword" in
  let H2 := fresh "Hdec" in
  assert (H1 : word_at p = Some w) by (vm_compute; reflexivity);
  assert (H2 : decode w = Some ins) by (vm_compute; reflexivity);
  k H1 H2.

Lemma i64_lt : (64 < 2 ^ 64)%nat.
Proof. apply Nat.pow_gt_lin_r; lia. Qed.

Lemma rest_lt64 : forall filled rest,
  (filled + rest < 2 ^ 64)%nat -> (rest < 2 ^ 64)%nat.
Proof. intros filled rest H. lia. Qed.
Lemma imm_bound : forall k, (k <= 64)%nat -> (k < 2 ^ 64)%nat.
Proof.
  intros k Hk. apply Nat.le_lt_trans with 64%nat; [exact Hk | exact i64_lt].
Qed.

Definition halted (b : N) (n : nat) (s : Mach) : Prop :=
  s.(done) = true /\ s.(r0) = 0 /\ s.(mem) = repeat b n.

Lemma more : forall k1 s s1 (P : Mach -> Prop),
  steps k1 s = Some s1 ->
  s1.(done) = false ->
  (exists k s2, steps k s1 = Some s2 /\ P s2) ->
  exists k s2, steps k s = Some s2 /\ P s2.
Proof.
  intros k1 s s1 P H1 Hd [k [s2 [Hk HP]]].
  exists (k1 + k)%nat, s2.
  split; [eapply steps_seq; eassumption | exact HP].
Qed.

(* Seven instructions: copy the base, build the byte splat, compare with 16. *)
Lemma prologue : forall (bn n : nat),
  (bn < 256)%nat ->
  (n < 2 ^ 64)%nat ->
  steps 7%nat (init bn n) =
  Some (canon (N.of_nat bn) 0%nat n 28 ((16 <=? n)%nat) ((n =? 16)%nat) false).
Proof.
  intros bn n Hb Hn.
  pose proof (chain_byte bn Hb) as Hc. cbn zeta in Hc.
  destruct Hc as [Ho8 [Ho16 [Ho32 Hand]]].
  set (a := N.of_nat bn).
  apply step_then with
    (s' := Mk 0 a (N.of_nat n) 0 0 0 0 (repeat 0 n) 4 false false false false).
  { reflexivity. }
  { subst a. apply mov_step. }
  apply step_then with
    (s' := Mk 0 a (N.of_nat n) 0 0 0 0 (repeat 0 n) 8 false false false false).
  { reflexivity. }
  { unfold step_at. cbn [pc]. red_at 4. cbn iota beta. unfold step.
    cbn [getr setr setpc r1]. subst a. rewrite Hand. reflexivity. }
  apply step_then with
    (s' := Mk 0 (a * 0x101) (N.of_nat n) 0 0 0 0 (repeat 0 n) 12 false false false false).
  { reflexivity. }
  { unfold step_at. cbn [pc]. red_at 8. cbn iota beta. unfold step.
    cbn [getr setr setpc r1]. subst a. rewrite Ho8. reflexivity. }
  apply step_then with
    (s' := Mk 0 (a * 0x01010101) (N.of_nat n) 0 0 0 0 (repeat 0 n) 16 false false false false).
  { reflexivity. }
  { unfold step_at. cbn [pc]. red_at 12. cbn iota beta. unfold step.
    cbn [getr setr setpc r1]. subst a. rewrite Ho16. reflexivity. }
  apply step_then with
    (s' := Mk 0 (a * 0x01010101) (N.of_nat n) (a * 0x0101010101010101) 0
              0 0 (repeat 0 n) 20 false false false false).
  { reflexivity. }
  { unfold step_at. cbn [pc]. red_at 16. cbn iota beta. unfold step.
    cbn [getr setr setpc r1]. subst a. rewrite Ho32. reflexivity. }
  apply step_then with
    (s' := Mk 0 (a * 0x01010101) (N.of_nat n) (a * 0x0101010101010101) 0
              (a * 0x0101010101010101) (a * 0x0101010101010101)
              (repeat 0 n) 24 false false false false).
  { reflexivity. }
  { unfold step_at. cbn [pc]. red_at 20. cbn iota beta. unfold step.
    cbn [getr N.eqb setdup r3]. reflexivity. }
  apply step_then with
    (s' := canon a 0%nat n 28 ((16 <=? n)%nat) ((n =? 16)%nat) false).
  { reflexivity. }
  { unfold step_at. cbn [pc]. red_at 24. cbn iota beta. unfold step.
    cbn [getr setr setflags setpc r2].
    change 16 with (N.of_nat 16%nat).
    rewrite (flag_C n 16%nat) by (first [exact Hn | apply imm_bound; lia]).
    rewrite (flag_Z n 16%nat) by (first [exact Hn | apply imm_bound; lia]).
    subst a. unfold canon, lowb, splatb. reflexivity. }
  { subst a. reflexivity. }
Qed.

Lemma peel_cmp : forall b filled rest imm (dest next p : N) c z qs (off : Z) w1 w2,
  b < 256 ->
  (rest < 2 ^ 64)%nat ->
  (imm <= 64)%nat ->
  word_at p = Some w1 ->
  decode w1 = Some (AddSub true true 64 31 2 (N.of_nat imm)) ->
  word_at (p + 4) = Some w2 ->
  decode w2 = Some (Bcond off 3) ->
  pc_add (p + 4) off = dest ->
  (p + 4) + 4 = next ->
  steps 2%nat (canon b filled rest p c z qs) =
  Some (canon b filled rest
          (if (imm <=? rest)%nat then next else dest)
          ((imm <=? rest)%nat) ((rest =? imm)%nat) qs).
Proof.
  intros b filled rest imm dest next p c z qs off w1 w2
         Hb Hr Hi Hw1 Hd1 Hw2 Hd2 Hdest Hnext.
  apply step_then with
    (s' := canon b filled rest (p + 4)
             ((imm <=? rest)%nat) ((rest =? imm)%nat) qs).
  - reflexivity.
  - unfold canon. etransitivity.
    + eapply (step_cmp _ _ _ _ _ _ _ _ _ _ _ rest imm);
        [exact Hr | apply imm_bound; exact Hi | exact Hw1 | exact Hd1].
    + unfold canon. reflexivity.
  - apply step_then with
      (s' := canon b filled rest
               (if (imm <=? rest)%nat then next else dest)
               ((imm <=? rest)%nat) ((rest =? imm)%nat) qs).
    + reflexivity.
    + assert (Ht : take_cond ((imm <=? rest)%nat) 3 =
                   Some (negb ((imm <=? rest)%nat))) by reflexivity.
      unfold canon. etransitivity.
      * eapply step_bcond; [exact Hw2 | exact Hd2 | exact Ht].
      * unfold canon. rewrite Hdest.
        destruct ((imm <=? rest)%nat); cbn [negb].
        -- rewrite <- Hnext. reflexivity.
        -- reflexivity.
    + reflexivity.
Qed.

Lemma cmp_hs : forall b filled rest imm (dest next p : N) c z qs (off : Z) w1 w2,
  b < 256 ->
  (rest < 2 ^ 64)%nat ->
  (imm <= 64)%nat ->
  word_at p = Some w1 ->
  decode w1 = Some (AddSub true true 64 31 2 (N.of_nat imm)) ->
  word_at (p + 4) = Some w2 ->
  decode w2 = Some (Bcond off 2) ->
  pc_add (p + 4) off = dest ->
  (p + 4) + 4 = next ->
  steps 2%nat (canon b filled rest p c z qs) =
  Some (canon b filled rest
          (if (imm <=? rest)%nat then dest else next)
          ((imm <=? rest)%nat) ((rest =? imm)%nat) qs).
Proof.
  intros b filled rest imm dest next p c z qs off w1 w2
         Hb Hr Hi Hw1 Hd1 Hw2 Hd2 Hdest Hnext.
  apply step_then with
    (s' := canon b filled rest (p + 4)
             ((imm <=? rest)%nat) ((rest =? imm)%nat) qs).
  - reflexivity.
  - unfold canon. etransitivity.
    + eapply (step_cmp _ _ _ _ _ _ _ _ _ _ _ rest imm);
        [exact Hr | apply imm_bound; exact Hi | exact Hw1 | exact Hd1].
    + unfold canon. reflexivity.
  - apply step_then with
      (s' := canon b filled rest
               (if (imm <=? rest)%nat then dest else next)
               ((imm <=? rest)%nat) ((rest =? imm)%nat) qs).
    + reflexivity.
    + assert (Ht : take_cond ((imm <=? rest)%nat) 2 =
                   Some ((imm <=? rest)%nat)) by reflexivity.
      unfold canon. etransitivity.
      * eapply step_bcond; [exact Hw2 | exact Hd2 | exact Ht].
      * unfold canon. rewrite Hdest.
        destruct ((imm <=? rest)%nat); cbn [negb].
        -- reflexivity.
        -- rewrite <- Hnext. reflexivity.
    + reflexivity.
Qed.

Lemma store_pair : forall b filled rest k (p : N) c z qs w1 w2,
  b < 256 ->
  (k <= rest)%nat ->
  (k <= 8)%nat ->
  (rest < 2 ^ 64)%nat ->
  word_at p = Some w1 ->
  decode w1 = Some (StrPost k 3 0 (Z.of_nat k)) ->
  word_at (p + 4) = Some w2 ->
  decode w2 = Some (AddSub true false 64 2 2 (N.of_nat k)) ->
  steps 2%nat (canon b filled rest p c z qs) =
  Some (canon b (filled + k)%nat (rest - k) ((p + 4) + 4) c z qs).
Proof.
  intros b filled rest k p c z qs w1 w2 Hb Hk H8 Hr Hw1 Hd1 Hw2 Hd2.
  apply step_then with
    (s' := Mk (N.of_nat (filled + k)) (lowb b) (N.of_nat rest) (splatb b) 0
              (splatb b) (splatb b)
              (repeat b (filled + k) ++ repeat 0 (rest - k))
              (p + 4) c z false qs).
  - reflexivity.
  - unfold canon. eapply step_strk; [exact Hb | exact Hk | exact H8 | exact Hw1 | exact Hd1].
  - apply step_then with
      (s' := canon b (filled + k)%nat (rest - k) ((p + 4) + 4) c z qs).
    + reflexivity.
    + unfold canon. etransitivity.
      * eapply step_sub2; [exact Hk | exact Hr | exact Hw2 | exact Hd2].
      * unfold canon. reflexivity.
    + reflexivity.
Qed.

Lemma from_152 : forall b filled rest c z qs,
  b < 256 ->
  (rest < 2)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  exists k (s : Mach),
    steps k (canon b filled rest 152 c z qs) = Some s /\
    halted b (filled + rest) s.
Proof.
  intros b filled rest c z qs Hb Hr Hlt.
  destruct rest as [|rest1].
  - assert (Hgo : steps 3%nat (canon b filled 0%nat 152 c z qs) =
      Some (Mk 0 (lowb b) (N.of_nat 0) (splatb b) 0
               (splatb b) (splatb b)
               (repeat b filled ++ repeat 0 0)
               164 c z true qs)).
    { unfold canon.
      apply step_then with
        (s' := Mk (N.of_nat filled) (lowb b) (N.of_nat 0) (splatb b) 0
                  (splatb b) (splatb b)
                  (repeat b filled ++ repeat 0 0)
                  (if (0 =? 0)%nat then pc_add 152 2%Z else 152 + 4)
                  c z false qs).
      - reflexivity.
      - word_pair 152 (Cbz 2 2%Z)
          ltac:(fun Hw Hd => eapply step_cbz; [exact Hw | exact Hd]).
      - cbn [Nat.eqb].
        replace (pc_add 152 2%Z) with 160 by (vm_compute; reflexivity).
        apply epilogue. }
    exists 3%nat.
    eexists. split; [exact Hgo|].
    unfold halted. cbn [done r0 mem].
    split. reflexivity.
    split. reflexivity.
    rewrite app_nil_r. rewrite Nat.add_0_r. reflexivity.
  - destruct rest1; [|lia].
    assert (Hgo : steps 4%nat (canon b filled 1%nat 152 c z qs) =
      Some (Mk 0 (lowb b) (N.of_nat 1) (splatb b) 0
               (splatb b) (splatb b)
               (repeat b (filled + 1) ++ repeat 0 0)
               164 c z true qs)).
    { unfold canon.
      apply step_then with
        (s' := Mk (N.of_nat filled) (lowb b) (N.of_nat 1) (splatb b) 0
                  (splatb b) (splatb b)
                  (repeat b filled ++ repeat 0 1)
                  (if (1 =? 0)%nat then pc_add 152 2%Z else 152 + 4)
                  c z false qs).
      - reflexivity.
      - word_pair 152 (Cbz 2 2%Z)
          ltac:(fun Hw Hd => eapply step_cbz; [exact Hw | exact Hd]).
      - cbn [Nat.eqb].
        apply step_then with
          (s' := Mk (N.of_nat filled) (lowb b) (N.of_nat 1) (splatb b) 0
                    (splatb b) (splatb b)
                    (repeat b (filled + 1) ++ repeat 0 (1 - 1))
                    ((152 + 4) + 4) c z false qs).
        + reflexivity.
        + word_pair (152 + 4) (StrB 3 0 0)
            ltac:(fun Hw Hd =>
              eapply step_strb; [exact Hb | lia | exact Hw | exact Hd]).
        + replace ((152 + 4) + 4) with 160 by reflexivity.
          replace (1 - 1)%nat with 0%nat by lia.
          apply epilogue. }
    exists 4%nat. eexists. split; [exact Hgo|].
    unfold halted. cbn [done r0 mem].
    split. reflexivity.
    split. reflexivity.
    rewrite app_nil_r. reflexivity.
Qed.
(* --- bit tests for a remainder under 16 --- *)

Lemma bits_lt16 : forall n,
  (n < 16)%nat ->
  N.testbit (N.of_nat n) 3 = (8 <=? n)%nat /\
  N.testbit (N.of_nat n) 2 = (4 <=? Nat.modulo n 8)%nat /\
  N.testbit (N.of_nat n) 1 = (2 <=? Nat.modulo n 4)%nat /\
  N.testbit (N.of_nat n) 0 = Nat.odd n.
Proof.
  intros n Hn.
  set (f := fun n =>
    Bool.eqb (N.testbit (N.of_nat n) 3) ((8 <=? n)%nat) &&
    Bool.eqb (N.testbit (N.of_nat n) 2) ((4 <=? Nat.modulo n 8)%nat) &&
    Bool.eqb (N.testbit (N.of_nat n) 1) ((2 <=? Nat.modulo n 4)%nat) &&
    Bool.eqb (N.testbit (N.of_nat n) 0) (Nat.odd n)).
  assert (Hf : f n = true).
  { apply (forallb_seq_from f 0%nat 16%nat n).
    - exact bit_table.
    - lia. }
  unfold f in Hf.
  apply andb_true_iff in Hf. destruct Hf as [Hf H0].
  apply andb_true_iff in Hf. destruct Hf as [Hf H1].
  apply andb_true_iff in Hf. destruct Hf as [H3 H2].
  apply eqb_prop in H3. apply eqb_prop in H2.
  apply eqb_prop in H1. apply eqb_prop in H0.
  split; [exact H3 | split; [exact H2 | split; [exact H1 | exact H0]]].
Qed.

Lemma bit3_lt16 : forall n, (n < 16)%nat ->
  N.testbit (N.of_nat n) 3 = (8 <=? n)%nat.
Proof. intros n Hn. apply bits_lt16. exact Hn. Qed.

Lemma bit2_lt8 : forall n, (n < 8)%nat ->
  N.testbit (N.of_nat n) 2 = (4 <=? n)%nat.
Proof.
  intros n Hn.
  destruct (bits_lt16 n ltac:(lia)) as [_ [H2 _]].
  rewrite H2. rewrite (Nat.mod_small n 8 Hn). reflexivity.
Qed.

Lemma bit1_lt4 : forall n, (n < 4)%nat ->
  N.testbit (N.of_nat n) 1 = (2 <=? n)%nat.
Proof.
  intros n Hn.
  destruct (bits_lt16 n ltac:(lia)) as [_ [_ [H1 _]]].
  rewrite H1. rewrite (Nat.mod_small n 4 Hn). reflexivity.
Qed.

Lemma bit0_lt2 : forall n, (n < 2)%nat ->
  N.testbit (N.of_nat n) 0 = (n =? 1)%nat.
Proof.
  intros n Hn.
  destruct (bits_lt16 n ltac:(lia)) as [_ [_ [_ H0]]].
  rewrite H0.
  destruct n as [|n]; [reflexivity|].
  destruct n as [|n]; [reflexivity|lia].
Qed.

(* One cbz. Taken when the remainder is zero. *)
Lemma step1_cbz : forall b filled rest (p dest next : N) (off : Z) c z qs w,
  word_at p = Some w ->
  decode w = Some (Cbz 2 off) ->
  pc_add p off = dest ->
  p + 4 = next ->
  steps 1%nat (canon b filled rest p c z qs) =
  Some (canon b filled rest (if (rest =? 0)%nat then dest else next) c z qs).
Proof.
  intros b filled rest p dest next off c z qs w Hw Hd Hdest Hnext.
  apply step_then with
    (s' := canon b filled rest (if (rest =? 0)%nat then dest else next) c z qs).
  - reflexivity.
  - unfold canon. etransitivity.
    + eapply step_cbz; [exact Hw | exact Hd].
    + unfold canon. rewrite Hdest.
      destruct (rest =? 0)%nat; [reflexivity | rewrite <- Hnext; reflexivity].
  - reflexivity.
Qed.

(* One tbz. The branch is taken when the tested bit is clear. *)
Lemma step1_tbz : forall b filled rest (p bit dest next : N) (off : Z) (go : bool)
                         c z qs w,
  word_at p = Some w ->
  decode w = Some (Tbz 2 bit off) ->
  pc_add p off = dest ->
  p + 4 = next ->
  N.testbit (N.of_nat rest) bit = go ->
  steps 1%nat (canon b filled rest p c z qs) =
  Some (canon b filled rest (if go then next else dest) c z qs).
Proof.
  intros b filled rest p bit dest next off go c z qs w Hw Hd Hdest Hnext Hbit.
  apply step_then with
    (s' := canon b filled rest (if go then next else dest) c z qs).
  - reflexivity.
  - unfold canon. etransitivity.
    + eapply step_tbz; [exact Hw | exact Hd].
    + unfold canon. rewrite Hbit, Hdest.
      destruct go; [rewrite <- Hnext; reflexivity | reflexivity].
  - reflexivity.
Qed.

(* Reach ret with a filled buffer and no bytes left. *)
Lemma finish0 : forall k b n r0 r1 r2 r3 lo hi c z qs s0,
  steps k s0 =
    Some (Mk r0 r1 r2 r3 0 lo hi (repeat b n ++ repeat 0 0) 160 c z false qs) ->
  exists k' (s : Mach), steps k' s0 = Some s /\ halted b n s.
Proof.
  intros k b n r0 r1 r2 r3 lo hi c z qs s0 H.
  exists (k + 2)%nat.
  eexists. split.
  - eapply steps_seq; [exact H | reflexivity | apply epilogue].
  - unfold halted.
    split. reflexivity.
    split. reflexivity.
    apply app_nil_r.
Qed.

Lemma two_nops : forall b filled rest c z qs,
  steps 2%nat (canon b filled rest 40 c z qs) =
  Some (canon b filled rest 48 c z qs).
Proof.
  intros b filled rest c z qs.
  apply step_then with (s' := canon b filled rest 44 c z qs).
  - reflexivity.
  - unfold canon. etransitivity.
    + word_pair 40 Nop ltac:(fun Hw Hd => eapply step_nop; [exact Hw | exact Hd]).
    + unfold canon. reflexivity.
  - apply step_then with (s' := canon b filled rest 48 c z qs).
    + reflexivity.
    + unfold canon. etransitivity.
      * word_pair 44 Nop ltac:(fun Hw Hd => eapply step_nop; [exact Hw | exact Hd]).
      * unfold canon. reflexivity.
    + reflexivity.
Qed.

(* str q0, [x0], #16; sub x2, x2, #16; cmp; b.hs. Four instructions. *)
Lemma body16 : forall b filled rest c z qs,
  b < 256 ->
  (16 <= rest)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  steps 4%nat (canon b filled rest 84 c z qs) =
  Some (canon b (filled + 16)%nat (rest - 16)
          (if (16 <=? rest - 16)%nat then 84 else 100)
          ((16 <=? rest - 16)%nat)
          (((rest - 16) =? 16)%nat) true).
Proof.
  intros b filled rest c z qs Hb H16 Hlt.
  assert (Hr : (rest < 2 ^ 64)%nat) by (exact (rest_lt64 filled rest Hlt)).
  assert (Hr16 : (rest - 16 < 2 ^ 64)%nat) by lia.
  assert (Hi : (16 <= 64)%nat) by lia.
  apply step_then with
    (s' := Mk (N.of_nat (filled + 16)) (lowb b) (N.of_nat rest) (splatb b) 0
              (splatb b) (splatb b)
              (repeat b (filled + 16) ++ repeat 0 (rest - 16))
              (84 + 4) c z false true).
  { reflexivity. }
  { unfold canon.
    word_pair 84 (StrQ 0 0 16%Z)
      ltac:(fun Hw Hd => eapply step_strq; [exact Hb | exact H16 | exact Hw | exact Hd]). }
  apply step_then with
    (s' := canon b (filled + 16)%nat (rest - 16) 92 c z true).
  { reflexivity. }
  { etransitivity.
    - word_pair (84 + 4) (AddSub true false 64 2 2 (N.of_nat 16))
        ltac:(fun Hw Hd => eapply step_sub2; [exact H16 | exact Hr | exact Hw | exact Hd]).
    - unfold canon. reflexivity. }
  word_pair 92 (AddSub true true 64 31 2 (N.of_nat 16))
    ltac:(fun Hw Hd =>
      word_pair 96 (Bcond (-3)%Z 2)
        ltac:(fun Hw2 Hd2 =>
          assert (Hdest : pc_add (92 + 4) (-3)%Z = 84) by (vm_compute; reflexivity);
          assert (Hnext : (92 + 4) + 4 = 100) by reflexivity;
          apply (cmp_hs b (filled + 16)%nat (rest - 16) 16%nat 84 100 92
                        c z true (-3)%Z _ _
                        Hb Hr16 Hi Hw Hd Hw2 Hd2 Hdest Hnext))).
Qed.

Lemma run16 : forall q b filled r c z qs,
  b < 256 ->
  (r < 16)%nat ->
  (filled + (16 * S q + r) < 2 ^ 64)%nat ->
  steps (4 * S q)%nat
    (canon b filled (16 * S q + r)%nat 84 c z qs) =
  Some (canon b (filled + 16 * S q)%nat r 100 false false true).
Proof.
  induction q as [|q IH]; intros b filled r c z qs Hb Hr Hlt.
  - replace (4 * S 0)%nat with 4%nat by reflexivity.
    replace (16 * S 0 + r)%nat with (16 + r)%nat by lia.
    replace (filled + 16 * S 0)%nat with (filled + 16)%nat by lia.
    assert (Hge : (16 <= 16 + r)%nat) by lia.
    assert (Hbody := body16 b filled (16 + r)%nat c z qs Hb Hge ltac:(lia)).
    replace ((16 + r) - 16)%nat with r in Hbody by lia.
    rewrite (proj2 (Nat.leb_gt 16 r) Hr) in Hbody.
    assert (Heqb : (r =? 16)%nat = false) by (apply Nat.eqb_neq; lia).
    rewrite Heqb in Hbody.
    exact Hbody.
  - replace (4 * S (S q))%nat with (4 + 4 * S q)%nat by lia.
    assert (Hge : (16 <= 16 * S (S q) + r)%nat) by lia.
    assert (Hbody := body16 b filled (16 * S (S q) + r)%nat c z qs Hb Hge Hlt).
    replace ((16 * S (S q) + r) - 16)%nat with (16 * S q + r)%nat in Hbody by lia.
    assert (Hle : (16 <= 16 * S q + r)%nat) by lia.
    rewrite (proj2 (Nat.leb_le 16 (16 * S q + r)) Hle) in Hbody.
    cbn iota in Hbody.
    replace (filled + 16 * S (S q))%nat with ((filled + 16) + 16 * S q)%nat by lia.
    eapply steps_seq; [exact Hbody | apply canon_done |].
    apply IH; [exact Hb | exact Hr | lia].
Qed.

(* stp; stp; add; sub; cmp; b.hs. Six instructions, 64 bytes. *)
Lemma body64 : forall b filled rest c z qs,
  b < 256 ->
  (64 <= rest)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  steps 6%nat (canon b filled rest 48 c z qs) =
  Some (canon b (filled + 64)%nat (rest - 64)
          (if (64 <=? rest - 64)%nat then 48 else 72)
          ((64 <=? rest - 64)%nat)
          (((rest - 64) =? 64)%nat) true).
Proof.
  intros b filled rest c z qs Hb H64 Hlt.
  assert (Hr : (rest < 2 ^ 64)%nat) by (exact (rest_lt64 filled rest Hlt)).
  assert (Ha : (filled + 64 < 2 ^ 64)%nat) by lia.
  assert (Hr64 : (rest - 64 < 2 ^ 64)%nat) by lia.
  assert (Hi : (64 <= 64)%nat) by lia.
  apply step_then with
    (s' := Mk (N.of_nat filled) (lowb b) (N.of_nat rest) (splatb b) 0
              (splatb b) (splatb b)
              (repeat b (filled + 32) ++ repeat 0 (rest - 32))
              52 c z false true).
  { reflexivity. }
  { apply stp48; [exact Hb | lia]. }
  apply step_then with
    (s' := Mk (N.of_nat filled) (lowb b) (N.of_nat rest) (splatb b) 0
              (splatb b) (splatb b)
              (repeat b (filled + 32 + 32) ++ repeat 0 ((rest - 32) - 32))
              (52 + 4) c z false true).
  { reflexivity. }
  { word_pair 52 (StpQ 0 0 0 (Z.of_nat 32))
      ltac:(fun Hw Hd => eapply step_stp; [exact Hb | lia | exact Hw | exact Hd]). }
  apply step_then with
    (s' := Mk (N.of_nat (filled + 64)) (lowb b) (N.of_nat rest) (splatb b) 0
              (splatb b) (splatb b)
              (repeat b (filled + 32 + 32) ++ repeat 0 ((rest - 32) - 32))
              ((52 + 4) + 4) c z false true).
  { reflexivity. }
  { word_pair (52 + 4) (AddSub false false 64 0 0 (N.of_nat 64))
      ltac:(fun Hw Hd =>
        eapply (step_add0 (lowb b) (N.of_nat rest) (splatb b) 0
                  (splatb b) (splatb b)
                  (repeat b (filled + 32 + 32) ++ repeat 0 ((rest - 32) - 32))
                  (52 + 4) c z true filled 64%nat);
        [exact Ha | exact Hw | exact Hd]). }
  apply step_then with
    (s' := canon b (filled + 64)%nat (rest - 64) 64 c z true).
  { reflexivity. }
  { etransitivity.
    - word_pair ((52 + 4) + 4) (AddSub true false 64 2 2 (N.of_nat 64))
        ltac:(fun Hw Hd => eapply step_sub2; [exact H64 | exact Hr | exact Hw | exact Hd]).
    - unfold canon.
      replace (filled + 32 + 32)%nat with (filled + 64)%nat by lia.
      replace ((rest - 32) - 32)%nat with (rest - 64)%nat by lia.
      replace (((52 + 4) + 4) + 4) with 64 by reflexivity.
      reflexivity. }
  word_pair 64 (AddSub true true 64 31 2 (N.of_nat 64))
    ltac:(fun Hw Hd =>
      word_pair 68 (Bcond (-5)%Z 2)
        ltac:(fun Hw2 Hd2 =>
          assert (Hdest : pc_add (64 + 4) (-5)%Z = 48) by (vm_compute; reflexivity);
          assert (Hnext : (64 + 4) + 4 = 72) by reflexivity;
          apply (cmp_hs b (filled + 64)%nat (rest - 64) 64%nat 48 72 64
                        c z true (-5)%Z _ _
                        Hb Hr64 Hi Hw Hd Hw2 Hd2 Hdest Hnext))).
Qed.

Lemma run64 : forall q b filled r c z qs,
  b < 256 ->
  (r < 64)%nat ->
  (filled + (64 * S q + r) < 2 ^ 64)%nat ->
  steps (6 * S q)%nat
    (canon b filled (64 * S q + r)%nat 48 c z qs) =
  Some (canon b (filled + 64 * S q)%nat r 72 false false true).
Proof.
  induction q as [|q IH]; intros b filled r c z qs Hb Hr Hlt.
  - replace (6 * S 0)%nat with 6%nat by reflexivity.
    replace (64 * S 0 + r)%nat with (64 + r)%nat by lia.
    replace (filled + 64 * S 0)%nat with (filled + 64)%nat by lia.
    assert (Hge : (64 <= 64 + r)%nat) by lia.
    assert (Hsum : (filled + (64 + r) < 2 ^ 64)%nat) by lia.
    assert (Hbody := body64 b filled (64 + r)%nat c z qs Hb Hge Hsum).
    replace ((64 + r) - 64)%nat with r in Hbody by lia.
    rewrite (proj2 (Nat.leb_gt 64 r) Hr) in Hbody.
    assert (Heqb : (r =? 64)%nat = false) by (apply Nat.eqb_neq; lia).
    rewrite Heqb in Hbody.
    exact Hbody.
  - replace (6 * S (S q))%nat with (6 + 6 * S q)%nat by lia.
    assert (Hge : (64 <= 64 * S (S q) + r)%nat) by lia.
    assert (Hbody := body64 b filled (64 * S (S q) + r)%nat c z qs Hb Hge Hlt).
    replace ((64 * S (S q) + r) - 64)%nat with (64 * S q + r)%nat in Hbody by lia.
    assert (Hle : (64 <= 64 * S q + r)%nat) by lia.
    rewrite (proj2 (Nat.leb_le 64 (64 * S q + r)) Hle) in Hbody.
    cbn iota in Hbody.
    replace (filled + 64 * S (S q))%nat with ((filled + 64) + 64 * S q)%nat by lia.
    eapply steps_seq; [exact Hbody | apply canon_done |].
    apply IH; [exact Hb | exact Hr | lia].
Qed.
(* Reduce a branch that has already become if true / if false. *)
Ltac land_if H :=
  cbn [negb] in H;
  repeat match type of H with
  | context[if true then ?a else ?b] => change (if true then a else b) with a in H
  | context[if false then ?a else ?b] => change (if false then a else b) with b in H
  end.

(* cmp / b.lo, then either the store or the forward label. rest < 2 * imm. *)
Lemma from_136 : forall b filled rest c z qs,
  b < 256 ->
  (rest < 4)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  exists k (s : Mach),
    steps k (canon b filled rest 136 c z qs) = Some s /\
    halted b (filled + rest) s.
Proof.
  intros b filled rest c z qs Hb Hr Hlt.
  assert (Hrb : (rest < 2 ^ 64)%nat) by (exact (rest_lt64 filled rest Hlt)).
  assert (Hi : (2 <= 64)%nat) by lia.
  word_pair 136 (AddSub true true 64 31 2 (N.of_nat 2)) ltac:(fun _ _ => idtac).
  word_pair (136 + 4) (Bcond 3%Z 3) ltac:(fun _ _ => idtac).
  assert (Hdest : pc_add (136 + 4) 3%Z = 152) by (vm_compute; reflexivity).
  assert (Hnext : (136 + 4) + 4 = 144) by reflexivity.
  assert (Hpeel := peel_cmp b filled rest 2%nat 152 144 136 c z qs 3%Z _ _
                     Hb Hrb Hi Hword Hdec Hword0 Hdec0 Hdest Hnext).
  destruct (Nat.leb 2 rest) eqn:Hge.
  - land_if Hpeel.
    eapply more; [exact Hpeel | apply canon_done |].
    assert (Hk : (2 <= rest)%nat) by (apply Nat.leb_le; exact Hge).
    assert (H8 : (2 <= 8)%nat) by lia.
    word_pair 144 (StrPost 2%nat 3 0 (Z.of_nat 2)) ltac:(fun _ _ => idtac).
    word_pair (144 + 4) (AddSub true false 64 2 2 (N.of_nat 2)) ltac:(fun _ _ => idtac).
    assert (Hst := store_pair b filled rest 2%nat 144 true ((rest =? 2)%nat) qs _ _
                     Hb Hk H8 Hrb Hword1 Hdec1 Hword2 Hdec2).
    replace ((144 + 4) + 4) with 152 in Hst by reflexivity.
    eapply more; [exact Hst | apply canon_done |].
    destruct (from_152 b (filled + 2)%nat (rest - 2) true ((rest =? 2)%nat) qs
                Hb ltac:(lia) ltac:(lia)) as [k [s [Hk2 Hh]]].
    replace ((filled + 2) + (rest - 2))%nat with (filled + rest)%nat in Hh by lia.
    exists k, s. split; [exact Hk2 | exact Hh].
  - land_if Hpeel.
    eapply more; [exact Hpeel | apply canon_done |].
    apply from_152; [exact Hb | apply Nat.leb_gt; exact Hge | exact Hlt].
Qed.

Lemma from_120 : forall b filled rest c z qs,
  b < 256 ->
  (rest < 8)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  exists k (s : Mach),
    steps k (canon b filled rest 120 c z qs) = Some s /\
    halted b (filled + rest) s.
Proof.
  intros b filled rest c z qs Hb Hr Hlt.
  assert (Hrb : (rest < 2 ^ 64)%nat) by (exact (rest_lt64 filled rest Hlt)).
  assert (Hi : (4 <= 64)%nat) by lia.
  word_pair 120 (AddSub true true 64 31 2 (N.of_nat 4)) ltac:(fun _ _ => idtac).
  word_pair (120 + 4) (Bcond 3%Z 3) ltac:(fun _ _ => idtac).
  assert (Hdest : pc_add (120 + 4) 3%Z = 136) by (vm_compute; reflexivity).
  assert (Hnext : (120 + 4) + 4 = 128) by reflexivity.
  assert (Hpeel := peel_cmp b filled rest 4%nat 136 128 120 c z qs 3%Z _ _
                     Hb Hrb Hi Hword Hdec Hword0 Hdec0 Hdest Hnext).
  destruct (4 <=? rest)%nat eqn:Hge.
  - land_if Hpeel.
    eapply more; [exact Hpeel | apply canon_done |].
    assert (Hk : (4 <= rest)%nat) by (apply Nat.leb_le; exact Hge).
    assert (H8 : (4 <= 8)%nat) by lia.
    word_pair 128 (StrPost 4%nat 3 0 (Z.of_nat 4)) ltac:(fun _ _ => idtac).
    word_pair (128 + 4) (AddSub true false 64 2 2 (N.of_nat 4)) ltac:(fun _ _ => idtac).
    assert (Hst := store_pair b filled rest 4%nat 128 true ((rest =? 4)%nat) qs _ _
                     Hb Hk H8 Hrb Hword1 Hdec1 Hword2 Hdec2).
    replace ((128 + 4) + 4) with 136 in Hst by reflexivity.
    eapply more; [exact Hst | apply canon_done |].
    destruct (from_136 b (filled + 4)%nat (rest - 4) true ((rest =? 4)%nat) qs
                Hb ltac:(lia) ltac:(lia)) as [k [s [Hk2 Hh]]].
    replace ((filled + 4) + (rest - 4))%nat with (filled + rest)%nat in Hh by lia.
    exists k, s. split; [exact Hk2 | exact Hh].
  - land_if Hpeel.
    eapply more; [exact Hpeel | apply canon_done |].
    apply from_136; [exact Hb | apply Nat.leb_gt; exact Hge | exact Hlt].
Qed.

Lemma from_104 : forall b filled rest c z qs,
  b < 256 ->
  (rest < 16)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  exists k (s : Mach),
    steps k (canon b filled rest 104 c z qs) = Some s /\
    halted b (filled + rest) s.
Proof.
  intros b filled rest c z qs Hb Hr Hlt.
  assert (Hrb : (rest < 2 ^ 64)%nat) by (exact (rest_lt64 filled rest Hlt)).
  assert (Hi : (8 <= 64)%nat) by lia.
  word_pair 104 (AddSub true true 64 31 2 (N.of_nat 8)) ltac:(fun _ _ => idtac).
  word_pair (104 + 4) (Bcond 3%Z 3) ltac:(fun _ _ => idtac).
  assert (Hdest : pc_add (104 + 4) 3%Z = 120) by (vm_compute; reflexivity).
  assert (Hnext : (104 + 4) + 4 = 112) by reflexivity.
  assert (Hpeel := peel_cmp b filled rest 8%nat 120 112 104 c z qs 3%Z _ _
                     Hb Hrb Hi Hword Hdec Hword0 Hdec0 Hdest Hnext).
  destruct (8 <=? rest)%nat eqn:Hge.
  - land_if Hpeel.
    eapply more; [exact Hpeel | apply canon_done |].
    assert (Hk : (8 <= rest)%nat) by (apply Nat.leb_le; exact Hge).
    assert (H8 : (8 <= 8)%nat) by lia.
    word_pair 112 (StrPost 8%nat 3 0 (Z.of_nat 8)) ltac:(fun _ _ => idtac).
    word_pair (112 + 4) (AddSub true false 64 2 2 (N.of_nat 8)) ltac:(fun _ _ => idtac).
    assert (Hst := store_pair b filled rest 8%nat 112 true ((rest =? 8)%nat) qs _ _
                     Hb Hk H8 Hrb Hword1 Hdec1 Hword2 Hdec2).
    replace ((112 + 4) + 4) with 120 in Hst by reflexivity.
    eapply more; [exact Hst | apply canon_done |].
    destruct (from_120 b (filled + 8)%nat (rest - 8) true ((rest =? 8)%nat) qs
                Hb ltac:(lia) ltac:(lia)) as [k [s [Hk2 Hh]]].
    replace ((filled + 8) + (rest - 8))%nat with (filled + rest)%nat in Hh by lia.
    exists k, s. split; [exact Hk2 | exact Hh].
  - land_if Hpeel.
    eapply more; [exact Hpeel | apply canon_done |].
    apply from_120; [exact Hb | apply Nat.leb_gt; exact Hge | exact Hlt].
Qed.

Lemma from_100 : forall b filled rest c z qs,
  b < 256 ->
  (rest < 16)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  exists k (s : Mach),
    steps k (canon b filled rest 100 c z qs) = Some s /\
    halted b (filled + rest) s.
Proof.
  intros b filled rest c z qs Hb Hr Hlt.
  word_pair 100 (Cbz 2 15%Z) ltac:(fun _ _ => idtac).
  assert (Hdest : pc_add 100 15%Z = 160) by (vm_compute; reflexivity).
  assert (Hnext : 100 + 4 = 104) by reflexivity.
  assert (Hcb := step1_cbz b filled rest 100 160 104 15%Z c z qs _
                   Hword Hdec Hdest Hnext).
  destruct (rest =? 0)%nat eqn:Hz.
  - land_if Hcb.
    apply Nat.eqb_eq in Hz. subst rest.
    replace (filled + 0)%nat with filled by lia.
    apply finish0 in Hcb. exact Hcb.
  - land_if Hcb.
    eapply more; [exact Hcb | apply canon_done |].
    apply from_104; [exact Hb | exact Hr | exact Hlt].
Qed.

(* Sixteen-byte loop, then the tail. rest is at least 16 and below 64. *)
Lemma from_84 : forall b filled rest c z qs,
  b < 256 ->
  (16 <= rest)%nat ->
  (rest < 64)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  exists k (s : Mach),
    steps k (canon b filled rest 84 c z qs) = Some s /\
    halted b (filled + rest) s.
Proof.
  intros b filled rest c z qs Hb Hge Hlt64 Hlt.
  pose proof (Nat.div_mod rest 16 ltac:(lia)) as Hsplit.
  assert (Hmod : (rest mod 16 < 16)%nat) by (apply Nat.mod_upper_bound; lia).
  assert (Hpos : (0 < rest / 16)%nat) by (apply Nat.div_str_pos; lia).
  destruct (rest / 16)%nat as [|q] eqn:Hq; [lia|].
  assert (Hbd : (filled + (16 * S q + rest mod 16) < 2 ^ 64)%nat)
    by (rewrite <- Hsplit; exact Hlt).
  rewrite Hsplit.
  assert (Hrun := run16 q b filled (rest mod 16) c z qs Hb Hmod Hbd).
  eapply more; [exact Hrun | apply canon_done |].
  assert (Hbd2 : ((filled + 16 * S q) + rest mod 16 < 2 ^ 64)%nat)
    by (rewrite <- Nat.add_assoc; exact Hbd).
  destruct (from_100 b (filled + 16 * S q)%nat (rest mod 16) false false true
              Hb Hmod Hbd2) as [k [s [Hk Hh]]].
  assert (E : ((filled + 16 * S q) + rest mod 16 = filled + (16 * S q + rest mod 16))%nat)
    by (rewrite Nat.add_assoc; reflexivity).
  rewrite E in Hh.
  exists k, s. split; [exact Hk | exact Hh].
Qed.

Lemma from_72 : forall b filled rest c z qs,
  b < 256 ->
  (rest < 64)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  exists k (s : Mach),
    steps k (canon b filled rest 72 c z qs) = Some s /\
    halted b (filled + rest) s.
Proof.
  intros b filled rest c z qs Hb Hr Hlt.
  assert (Hrb : (rest < 2 ^ 64)%nat) by (exact (rest_lt64 filled rest Hlt)).
  word_pair 72 (Cbz 2 22%Z) ltac:(fun _ _ => idtac).
  assert (Hdest : pc_add 72 22%Z = 160) by (vm_compute; reflexivity).
  assert (Hnext : 72 + 4 = 76) by reflexivity.
  assert (Hcb := step1_cbz b filled rest 72 160 76 22%Z c z qs _
                   Hword Hdec Hdest Hnext).
  destruct (rest =? 0)%nat eqn:Hz.
  - land_if Hcb.
    apply Nat.eqb_eq in Hz. subst rest.
    replace (filled + 0)%nat with filled by lia.
    apply finish0 in Hcb. exact Hcb.
  - land_if Hcb.
    eapply more; [exact Hcb | apply canon_done |].
    assert (Hi : (16 <= 64)%nat) by lia.
    word_pair 76 (AddSub true true 64 31 2 (N.of_nat 16)) ltac:(fun _ _ => idtac).
    word_pair (76 + 4) (Bcond 6%Z 3) ltac:(fun _ _ => idtac).
    assert (Hd2 : pc_add (76 + 4) 6%Z = 104) by (vm_compute; reflexivity).
    assert (Hn2 : (76 + 4) + 4 = 84) by reflexivity.
    assert (Hpeel := peel_cmp b filled rest 16%nat 104 84 76 c z qs 6%Z _ _
                       Hb Hrb Hi Hword0 Hdec0 Hword1 Hdec1 Hd2 Hn2).
    destruct (16 <=? rest)%nat eqn:H16.
    + land_if Hpeel.
      eapply more; [exact Hpeel | apply canon_done |].
      apply from_84; [exact Hb | apply Nat.leb_le; exact H16 | exact Hr | exact Hlt].
    + land_if Hpeel.
      eapply more; [exact Hpeel | apply canon_done |].
      apply from_104; [exact Hb | apply Nat.leb_gt; exact H16 | exact Hlt].
Qed.

(* Sixty-four-byte loop, then whatever is left. *)
Lemma from_48 : forall b filled rest c z qs,
  b < 256 ->
  (64 <= rest)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  exists k (s : Mach),
    steps k (canon b filled rest 48 c z qs) = Some s /\
    halted b (filled + rest) s.
Proof.
  intros b filled rest c z qs Hb Hge Hlt.
  pose proof (Nat.div_mod rest 64 ltac:(lia)) as Hsplit.
  assert (Hmod : (rest mod 64 < 64)%nat) by (apply Nat.mod_upper_bound; lia).
  assert (Hpos : (0 < rest / 64)%nat) by (apply Nat.div_str_pos; lia).
  destruct (rest / 64)%nat as [|q] eqn:Hq; [lia|].
  assert (Hbd : (filled + (64 * S q + rest mod 64) < 2 ^ 64)%nat)
    by (rewrite <- Hsplit; exact Hlt).
  rewrite Hsplit.
  assert (Hrun := run64 q b filled (rest mod 64) c z qs Hb Hmod Hbd).
  eapply more; [exact Hrun | apply canon_done |].
  assert (Hbd2 : ((filled + 64 * S q) + rest mod 64 < 2 ^ 64)%nat)
    by (rewrite <- Nat.add_assoc; exact Hbd).
  destruct (from_72 b (filled + 64 * S q)%nat (rest mod 64) false false true
              Hb Hmod Hbd2) as [k [s [Hk Hh]]].
  assert (E : ((filled + 64 * S q) + rest mod 64 = filled + (64 * S q + rest mod 64))%nat)
    by (rewrite Nat.add_assoc; reflexivity).
  rewrite E in Hh.
  exists k, s. split; [exact Hk | exact Hh].
Qed.

Lemma from_32 : forall b filled rest c z qs,
  b < 256 ->
  (16 <= rest)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  exists k (s : Mach),
    steps k (canon b filled rest 32 c z qs) = Some s /\
    halted b (filled + rest) s.
Proof.
  intros b filled rest c z qs Hb Hge Hlt.
  assert (Hrb : (rest < 2 ^ 64)%nat) by (exact (rest_lt64 filled rest Hlt)).
  assert (Hi : (64 <= 64)%nat) by lia.
  word_pair 32 (AddSub true true 64 31 2 (N.of_nat 64)) ltac:(fun _ _ => idtac).
  word_pair (32 + 4) (Bcond 12%Z 3) ltac:(fun _ _ => idtac).
  assert (Hdest : pc_add (32 + 4) 12%Z = 84) by (vm_compute; reflexivity).
  assert (Hnext : (32 + 4) + 4 = 40) by reflexivity.
  assert (Hpeel := peel_cmp b filled rest 64%nat 84 40 32 c z qs 12%Z _ _
                     Hb Hrb Hi Hword Hdec Hword0 Hdec0 Hdest Hnext).
  destruct (64 <=? rest)%nat eqn:H64.
  - land_if Hpeel.
    eapply more; [exact Hpeel | apply canon_done |].
    eapply more; [apply two_nops | apply canon_done |].
    apply from_48; [exact Hb | apply Nat.leb_le; exact H64 | exact Hlt].
  - land_if Hpeel.
    eapply more; [exact Hpeel | apply canon_done |].
    apply from_84; [exact Hb | exact Hge | apply Nat.leb_gt; exact H64 | exact Hlt].
Qed.

(* Last bit of the short path: tbz #0, maybe one byte, then ret. *)
Lemma from_204 : forall b filled rest c z qs,
  b < 256 ->
  (rest < 2)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  exists k (s : Mach),
    steps k (canon b filled rest 204 c z qs) = Some s /\
    halted b (filled + rest) s.
Proof.
  intros b filled rest c z qs Hb Hr Hlt.
  assert (Hbit := bit0_lt2 rest Hr).
  word_pair 204 (Tbz 2 0 (-11)%Z) ltac:(fun _ _ => idtac).
  assert (Hdest : pc_add 204 (-11)%Z = 160) by (vm_compute; reflexivity).
  assert (Hnext : 204 + 4 = 208) by reflexivity.
  assert (Htb := step1_tbz b filled rest 204 0 160 208 (-11)%Z
                   ((rest =? 1)%nat) c z qs _
                   Hword Hdec Hdest Hnext Hbit).
  destruct rest as [|rest1].
  - cbn [Nat.eqb] in Htb. land_if Htb.
    replace (filled + 0)%nat with filled by lia.
    apply finish0 in Htb. exact Htb.
  - destruct rest1 as [|rest2]; [|lia].
    cbn [Nat.eqb] in Htb. land_if Htb.
    eapply more; [exact Htb | apply canon_done |].
    assert (Hst : steps 1%nat (canon b filled 1%nat 208 c z qs) =
      Some (Mk (N.of_nat filled) (lowb b) (N.of_nat 1) (splatb b) 0
               (splatb b) (splatb b)
               (repeat b (filled + 1) ++ repeat 0 (1 - 1))
               (208 + 4) c z false qs)).
    { apply step_then with
        (s' := Mk (N.of_nat filled) (lowb b) (N.of_nat 1) (splatb b) 0
                  (splatb b) (splatb b)
                  (repeat b (filled + 1) ++ repeat 0 (1 - 1))
                  (208 + 4) c z false qs).
      - reflexivity.
      - unfold canon.
        word_pair 208 (StrB 3 0 0)
          ltac:(fun Hw Hd => eapply step_strb; [exact Hb | lia | exact Hw | exact Hd]).
      - reflexivity. }
    replace (1 - 1)%nat with 0%nat in Hst by lia.
    replace (208 + 4) with 212 in Hst by reflexivity.
    assert (Hbr : steps 1%nat
        (Mk (N.of_nat filled) (lowb b) (N.of_nat 1) (splatb b) 0
            (splatb b) (splatb b)
            (repeat b (filled + 1) ++ repeat 0 0)
            212 c z false qs) =
      Some (Mk (N.of_nat filled) (lowb b) (N.of_nat 1) (splatb b) 0
               (splatb b) (splatb b)
               (repeat b (filled + 1) ++ repeat 0 0)
               160 c z false qs)).
    { apply step_then with
        (s' := Mk (N.of_nat filled) (lowb b) (N.of_nat 1) (splatb b) 0
                  (splatb b) (splatb b)
                  (repeat b (filled + 1) ++ repeat 0 0)
                  160 c z false qs).
      - reflexivity.
      - etransitivity.
        + word_pair 212 (B (-13)%Z)
            ltac:(fun Hw Hd => eapply step_b; [exact Hw | exact Hd]).
        + replace (pc_add 212 (-13)%Z) with 160 by (vm_compute; reflexivity).
          reflexivity.
      - reflexivity. }
    assert (Hgo : steps 2%nat (canon b filled 1%nat 208 c z qs) =
      Some (Mk (N.of_nat filled) (lowb b) (N.of_nat 1) (splatb b) 0
               (splatb b) (splatb b)
               (repeat b (filled + 1) ++ repeat 0 0)
               160 c z false qs)).
    { replace 2%nat with (1 + 1)%nat by reflexivity.
      eapply steps_seq; [exact Hst | reflexivity | exact Hbr]. }
    apply finish0 in Hgo. exact Hgo.
Qed.

Lemma from_192 : forall b filled rest c z qs,
  b < 256 ->
  (rest < 4)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  exists k (s : Mach),
    steps k (canon b filled rest 192 c z qs) = Some s /\
    halted b (filled + rest) s.
Proof.
  intros b filled rest c z qs Hb Hr Hlt.
  assert (Hrb : (rest < 2 ^ 64)%nat) by (exact (rest_lt64 filled rest Hlt)).
  assert (Hbit := bit1_lt4 rest Hr).
  word_pair 192 (Tbz 2 1 3%Z) ltac:(fun _ _ => idtac).
  assert (Hdest : pc_add 192 3%Z = 204) by (vm_compute; reflexivity).
  assert (Hnext : 192 + 4 = 196) by reflexivity.
  assert (Htb := step1_tbz b filled rest 192 1 204 196 3%Z
                   ((2 <=? rest)%nat) c z qs _
                   Hword Hdec Hdest Hnext Hbit).
  destruct (2 <=? rest)%nat eqn:Hge.
  - land_if Htb.
    eapply more; [exact Htb | apply canon_done |].
    assert (Hk : (2 <= rest)%nat) by (apply Nat.leb_le; exact Hge).
    assert (H8 : (2 <= 8)%nat) by lia.
    word_pair 196 (StrPost 2%nat 3 0 (Z.of_nat 2)) ltac:(fun _ _ => idtac).
    word_pair (196 + 4) (AddSub true false 64 2 2 (N.of_nat 2)) ltac:(fun _ _ => idtac).
    assert (Hst := store_pair b filled rest 2%nat 196 c z qs _ _
                     Hb Hk H8 Hrb Hword0 Hdec0 Hword1 Hdec1).
    replace ((196 + 4) + 4) with 204 in Hst by reflexivity.
    eapply more; [exact Hst | apply canon_done |].
    destruct (from_204 b (filled + 2)%nat (rest - 2) c z qs
                Hb ltac:(lia) ltac:(lia)) as [k [s [Hk2 Hh]]].
    replace ((filled + 2) + (rest - 2))%nat with (filled + rest)%nat in Hh by lia.
    exists k, s. split; [exact Hk2 | exact Hh].
  - land_if Htb.
    eapply more; [exact Htb | apply canon_done |].
    apply from_204; [exact Hb | apply Nat.leb_gt; exact Hge | exact Hlt].
Qed.

Lemma from_180 : forall b filled rest c z qs,
  b < 256 ->
  (rest < 8)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  exists k (s : Mach),
    steps k (canon b filled rest 180 c z qs) = Some s /\
    halted b (filled + rest) s.
Proof.
  intros b filled rest c z qs Hb Hr Hlt.
  assert (Hrb : (rest < 2 ^ 64)%nat) by (exact (rest_lt64 filled rest Hlt)).
  assert (Hbit := bit2_lt8 rest Hr).
  word_pair 180 (Tbz 2 2 3%Z) ltac:(fun _ _ => idtac).
  assert (Hdest : pc_add 180 3%Z = 192) by (vm_compute; reflexivity).
  assert (Hnext : 180 + 4 = 184) by reflexivity.
  assert (Htb := step1_tbz b filled rest 180 2 192 184 3%Z
                   ((4 <=? rest)%nat) c z qs _
                   Hword Hdec Hdest Hnext Hbit).
  destruct (4 <=? rest)%nat eqn:Hge.
  - land_if Htb.
    eapply more; [exact Htb | apply canon_done |].
    assert (Hk : (4 <= rest)%nat) by (apply Nat.leb_le; exact Hge).
    assert (H8 : (4 <= 8)%nat) by lia.
    word_pair 184 (StrPost 4%nat 3 0 (Z.of_nat 4)) ltac:(fun _ _ => idtac).
    word_pair (184 + 4) (AddSub true false 64 2 2 (N.of_nat 4)) ltac:(fun _ _ => idtac).
    assert (Hst := store_pair b filled rest 4%nat 184 c z qs _ _
                     Hb Hk H8 Hrb Hword0 Hdec0 Hword1 Hdec1).
    replace ((184 + 4) + 4) with 192 in Hst by reflexivity.
    eapply more; [exact Hst | apply canon_done |].
    destruct (from_192 b (filled + 4)%nat (rest - 4) c z qs
                Hb ltac:(lia) ltac:(lia)) as [k [s [Hk2 Hh]]].
    replace ((filled + 4) + (rest - 4))%nat with (filled + rest)%nat in Hh by lia.
    exists k, s. split; [exact Hk2 | exact Hh].
  - land_if Htb.
    eapply more; [exact Htb | apply canon_done |].
    apply from_192; [exact Hb | apply Nat.leb_gt; exact Hge | exact Hlt].
Qed.

Lemma from_168 : forall b filled rest c z qs,
  b < 256 ->
  (rest < 16)%nat ->
  (filled + rest < 2 ^ 64)%nat ->
  exists k (s : Mach),
    steps k (canon b filled rest 168 c z qs) = Some s /\
    halted b (filled + rest) s.
Proof.
  intros b filled rest c z qs Hb Hr Hlt.
  assert (Hrb : (rest < 2 ^ 64)%nat) by (exact (rest_lt64 filled rest Hlt)).
  assert (Hbit := bit3_lt16 rest Hr).
  word_pair 168 (Tbz 2 3 3%Z) ltac:(fun _ _ => idtac).
  assert (Hdest : pc_add 168 3%Z = 180) by (vm_compute; reflexivity).
  assert (Hnext : 168 + 4 = 172) by reflexivity.
  assert (Htb := step1_tbz b filled rest 168 3 180 172 3%Z
                   ((8 <=? rest)%nat) c z qs _
                   Hword Hdec Hdest Hnext Hbit).
  destruct (8 <=? rest)%nat eqn:Hge.
  - land_if Htb.
    eapply more; [exact Htb | apply canon_done |].
    assert (Hk : (8 <= rest)%nat) by (apply Nat.leb_le; exact Hge).
    assert (H8 : (8 <= 8)%nat) by lia.
    word_pair 172 (StrPost 8%nat 3 0 (Z.of_nat 8)) ltac:(fun _ _ => idtac).
    word_pair (172 + 4) (AddSub true false 64 2 2 (N.of_nat 8)) ltac:(fun _ _ => idtac).
    assert (Hst := store_pair b filled rest 8%nat 172 c z qs _ _
                     Hb Hk H8 Hrb Hword0 Hdec0 Hword1 Hdec1).
    replace ((172 + 4) + 4) with 180 in Hst by reflexivity.
    eapply more; [exact Hst | apply canon_done |].
    destruct (from_180 b (filled + 8)%nat (rest - 8) c z qs
                Hb ltac:(lia) ltac:(lia)) as [k [s [Hk2 Hh]]].
    replace ((filled + 8) + (rest - 8))%nat with (filled + rest)%nat in Hh by lia.
    exists k, s. split; [exact Hk2 | exact Hh].
  - land_if Htb.
    eapply more; [exact Htb | apply canon_done |].
    apply from_180; [exact Hb | apply Nat.leb_gt; exact Hge | exact Hlt].
Qed.

(* The compare-with-16 branch that the prologue leaves pending. *)
Lemma from_28 : forall b n c z qs,
  b < 256 ->
  (n < 2 ^ 64)%nat ->
  c = (16 <=? n)%nat ->
  exists k (s : Mach),
    steps k (canon b 0%nat n 28 c z qs) = Some s /\
    halted b n s.
Proof.
  intros b n c z qs Hb Hn Hc.
  assert (Hlt : (0 + n < 2 ^ 64)%nat) by (rewrite Nat.add_0_l; exact Hn).
  word_pair 28 (Bcond 35%Z 3) ltac:(fun _ _ => idtac).
  assert (Hdest : pc_add 28 35%Z = 168) by (vm_compute; reflexivity).
  assert (Hnext : 28 + 4 = 32) by reflexivity.
  assert (Ht : take_cond c 3 = Some (negb c)) by reflexivity.
  assert (Hbr : steps 1%nat (canon b 0%nat n 28 c z qs) =
            Some (canon b 0%nat n (if negb c then 168 else 32) c z qs)).
  { apply step_then with
      (s' := canon b 0%nat n (if negb c then 168 else 32) c z qs).
    - reflexivity.
    - unfold canon. etransitivity.
      + eapply step_bcond; [exact Hword | exact Hdec | exact Ht].
      + unfold canon. rewrite Hdest.
        destruct c; cbn [negb].
        * rewrite <- Hnext. reflexivity.
        * reflexivity.
    - reflexivity. }
  rewrite Hc in Hbr. rewrite Hc.
  destruct ((16 <=? n)%nat) eqn:H16.
  - land_if Hbr.
    eapply more; [exact Hbr | apply canon_done |].
    destruct (from_32 b 0%nat n true z qs Hb ltac:(apply Nat.leb_le; exact H16) Hlt)
      as [k [s [Hk Hh]]].
    rewrite Nat.add_0_l in Hh.
    exists k, s. split; [exact Hk | exact Hh].
  - land_if Hbr.
    eapply more; [exact Hbr | apply canon_done |].
    destruct (from_168 b 0%nat n false z qs Hb ltac:(apply Nat.leb_gt; exact H16) Hlt)
      as [k [s [Hk Hh]]].
    rewrite Nat.add_0_l in Hh.
    exists k, s. split; [exact Hk | exact Hh].
Qed.

Theorem rt_memset_neon_any :
  forall (n b : nat),
    (b < 256)%nat ->
    (n < 2 ^ 64)%nat ->
    exists k (s : Mach),
      steps k (init b n) = Some s /\
      s.(done) = true /\
      s.(r0) = 0 /\
      s.(mem) = repeat (N.of_nat b) n.
Proof.
  intros n b Hb Hn.
  assert (HbN : N.of_nat b < 256) by (apply of_nat_byte; exact Hb).
  eapply more.
  - apply (prologue b n Hb Hn).
  - apply canon_done.
  - destruct (from_28 (N.of_nat b) n ((16 <=? n)%nat) ((n =? 16)%nat) false
               HbN Hn eq_refl) as [k [s [Hk Hh]]].
    exists k, s. split; [exact Hk |].
    destruct Hh as [Hd [Hr0 Hm]].
    split; [exact Hd | split; [exact Hr0 | exact Hm]].
Qed.

Theorem rt_memset_neon_16 :
  forall b : nat,
    (b < 256)%nat ->
    exists k (s : Mach),
      steps k (init b 16) = Some s /\
      s.(done) = true /\
      s.(r0) = 0 /\
      s.(mem) = repeat (N.of_nat b) 16.
Proof.
  intros b Hb.
  apply rt_memset_neon_any; [exact Hb | apply imm_bound; lia].
Qed.
