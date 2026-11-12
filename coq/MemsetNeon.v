(* rt_memset_neon, the 16-byte case.
   Bytes are the Mach-O text of _rt_memset_neon from
   clang -arch arm64 -c src/aarch64/neon/mem.S
   (file offsets 0x130..0x20f). One NEON store: dup.2d then str q0, [x0], #16.
   Checked length is n = 16 only. Other lengths are not claims of this file. *)

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
| Ret : Insn.

Definition decode (w : N) : option Insn :=
  if N.eqb w 0xD65F03C0 then Some Ret
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

Fixpoint run (n : nat) (s : Mach) : option Mach :=
  match n with
  | O => None
  | S n => if s.(done) then Some s
           else match step_at s with
                | None => None
                | Some s' => run n s'
                end
  end.

Definition init (b : N) : Mach :=
  Mk 0 b 16 0 0 0 0 (repeat 0 32) 0 false false false false.

Fixpoint bytes_eq (a b : list N) : bool :=
  match a, b with
  | [], [] => true
  | x :: a, y :: b => N.eqb x y && bytes_eq a b
  | _, _ => false
  end.

(* Halted, returned the original pointer, executed str q, wrote 16 copies
   of b and left the following 16 bytes alone. *)
Definition byte_ok (b : nat) : bool :=
  match run 40 (init (N.of_nat b)) with
  | None => false
  | Some s =>
      s.(done) && s.(qstore) && N.eqb s.(r0) 0 &&
      bytes_eq s.(mem) (repeat (N.of_nat b) 16 ++ repeat 0 16)
  end.

Local Close Scope N_scope.
Local Open Scope nat_scope.

Lemma forallb_seq_from :
  forall (f : nat -> bool) start len i,
    forallb f (seq start len) = true ->
    start <= i < start + len ->
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

Theorem rt_memset_neon_16 :
  forall b : nat, b < 256 -> byte_ok b = true.
Proof.
  intros b Hb.
  apply (forallb_seq_from byte_ok 0 256 b).
  - vm_compute. reflexivity.
  - lia.
Qed.
