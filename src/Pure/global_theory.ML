(*  Title:      Pure/global_theory.ML
    Author:     Makarius

Global theory content: stored facts.
*)

signature GLOBAL_THEORY =
sig
  val facts_of: theory -> Facts.T
  val check_fact: theory -> xstring * Position.T -> string
  val intern_fact: theory -> xstring -> string
  val defined_fact: theory -> string -> bool
  val alias_fact: binding -> string -> theory -> theory
  val hide_fact: bool -> string -> theory -> theory
  val get_thms: theory -> xstring -> thm list
  val get_thm: theory -> xstring -> thm
  val transfer_theories: theory -> thm -> thm
  val all_thms_of: theory -> bool -> (string * thm) list
  val map_facts: ('a -> 'b) -> ('c * ('a list * 'd) list) list -> ('c * ('b list * 'd) list) list
  val burrow_fact: ('a list -> 'b list) -> ('a list * 'c) list -> ('b list * 'c) list
  val burrow_facts: ('a list -> 'b list) ->
    ('c * ('a list * 'd) list) list -> ('c * ('b list * 'd) list) list
  val name_multi: string -> 'a list -> (string * 'a) list
  val name_thm: bool -> bool -> string -> thm -> thm
  val name_thms: bool -> bool -> string -> thm list -> thm list
  val name_thmss: bool -> string -> (thm list * 'a) list -> (thm list * 'a) list
  val add_thms_lazy: string -> (binding * thm list lazy) -> theory -> theory
  val store_thm: binding * thm -> theory -> thm * theory
  val store_thm_open: binding * thm -> theory -> thm * theory
  val add_thms: ((binding * thm) * attribute list) list -> theory -> thm list * theory
  val add_thm: (binding * thm) * attribute list -> theory -> thm * theory
  val add_thmss: ((binding * thm list) * attribute list) list -> theory -> thm list list * theory
  val add_thms_dynamic': Context.generic -> binding * (Context.generic -> thm list) ->
    theory -> string * theory
  val add_thms_dynamic: binding * (Context.generic -> thm list) -> theory -> theory
  val note_thms: string -> Thm.binding * (thm list * attribute list) list -> theory ->
    (string * thm list) * theory
  val note_thmss: string -> (Thm.binding * (thm list * attribute list) list) list -> theory ->
    (string * thm list) list * theory
  val add_defs: bool -> ((binding * term) * attribute list) list ->
    theory -> thm list * theory
  val add_defs_unchecked: bool -> ((binding * term) * attribute list) list ->
    theory -> thm list * theory
end;

structure Global_Theory: GLOBAL_THEORY =
struct

(** theory data **)

structure Data = Theory_Data
(
  type T = Facts.T;
  val empty = Facts.empty;
  val extend = I;
  val merge = Facts.merge;
);

val facts_of = Data.get;

fun check_fact thy = Facts.check (Context.Theory thy) (facts_of thy);
val intern_fact = Facts.intern o facts_of;
val defined_fact = Facts.defined o facts_of;

fun alias_fact binding name thy =
  Data.map (Facts.alias (Sign.naming_of thy) binding name) thy;

fun hide_fact fully name = Data.map (Facts.hide fully name);


(* retrieve theorems *)

fun get_thms thy xname =
  #thms (Facts.retrieve (Context.Theory thy) (facts_of thy) (xname, Position.none));

fun get_thm thy xname =
  Facts.the_single (xname, Position.none) (get_thms thy xname);

fun transfer_theories thy =
  let
    val theories =
      fold (fn thy' => Symtab.update (Context.theory_name thy', thy'))
        (Theory.nodes_of thy) Symtab.empty;
    fun transfer th =
      Thm.transfer (the_default thy (Symtab.lookup theories (Thm.theory_name th))) th;
  in transfer end;

fun all_thms_of thy verbose =
  let
    val transfer = transfer_theories thy;
    val facts = facts_of thy;
    fun add (name, ths) =
      if not verbose andalso Facts.is_concealed facts name then I
      else append (map (`(Thm.get_name_hint) o transfer) ths);
  in Facts.fold_static add facts [] end;



(** store theorems **)

(* fact specifications *)

fun map_facts f = map (apsnd (map (apfst (map f))));
fun burrow_fact f = split_list #>> burrow f #> op ~~;
fun burrow_facts f = split_list ##> burrow (burrow_fact f) #> op ~~;


(* naming *)

fun name_multi name [x] = [(name, x)]
  | name_multi "" xs = map (pair "") xs
  | name_multi name xs = map_index (fn (i, x) => (name ^ "_" ^ string_of_int (i + 1), x)) xs;

fun name_thm pre official name thm = thm
  |> (if not official orelse pre andalso Thm.derivation_name thm <> "" then I
      else Thm.name_derivation name)
  |> (if name = "" orelse pre andalso Thm.has_name_hint thm then I
      else Thm.put_name_hint name);

fun name_thms pre official name thms =
  map (uncurry (name_thm pre official)) (name_multi name thms);

fun name_thmss official name fact =
  burrow_fact (name_thms true official name) fact;


(* enter_thms *)

fun register_proofs thms thy = (thms, Thm.register_proofs (Lazy.value thms) thy);

fun add_facts arg thy =
  thy |> Data.map (Facts.add_static (Context.Theory thy) {strict = true, index = false} arg #> #2);

fun add_thms_lazy kind (b, thms) thy =
  if Binding.is_empty b then Thm.register_proofs thms thy
  else
    let
      val name = Sign.full_name thy b;
      val thms' = thms
        |> Lazy.map_finished (name_thms true true name #> map (Thm.kind_rule kind));
    in thy |> Thm.register_proofs thms' |> add_facts (b, thms') end;

fun enter_thms pre_name post_name app_att (b, thms) thy =
  if Binding.is_empty b then app_att thms thy |-> register_proofs
  else
    let
      val name = Sign.full_name thy b;
      val (thms', thy') =
        app_att (pre_name name thms) thy |>> post_name name |-> register_proofs;
      val thy'' = thy' |> add_facts (b, Lazy.value thms');
    in (map (Thm.transfer thy'') thms', thy'') end;


(* store_thm *)

fun store_thm (b, th) =
  enter_thms (name_thms true true) (name_thms false true) pair (b, [th]) #>> the_single;

fun store_thm_open (b, th) =
  enter_thms (name_thms true false) (name_thms false false) pair (b, [th]) #>> the_single;


(* add_thms(s) *)

fun add_thms_atts pre_name ((b, thms), atts) =
  enter_thms pre_name (name_thms false true) (fold_map (Thm.theory_attributes atts)) (b, thms);

fun gen_add_thmss pre_name =
  fold_map (add_thms_atts pre_name);

fun gen_add_thms pre_name args =
  apfst (map hd) o gen_add_thmss pre_name (map (apfst (apsnd single)) args);

val add_thmss = gen_add_thmss (name_thms true true);
val add_thms = gen_add_thms (name_thms true true);
val add_thm = yield_singleton add_thms;


(* dynamic theorems *)

fun add_thms_dynamic' context arg thy =
  let val (name, facts') = Facts.add_dynamic context arg (Data.get thy)
  in (name, Data.put facts' thy) end;

fun add_thms_dynamic arg thy =
  add_thms_dynamic' (Context.Theory thy) arg thy |> snd;


(* note_thmss *)

fun note_thms kind ((b, more_atts), facts) thy =
  let
    val name = Sign.full_name thy b;
    fun app (ths, atts) =
      fold_map (Thm.theory_attributes (surround (Thm.kind kind) (atts @ more_atts))) ths;
    val (thms, thy') =
      enter_thms (name_thmss true) (name_thms false true) (apfst flat oo fold_map app)
        (b, facts) thy;
  in ((name, thms), thy') end;

val note_thmss = fold_map o note_thms;


(* old-style defs *)

local

fun add unchecked overloaded = fold_map (fn ((b, prop), atts) => fn thy =>
  let
    val context = Defs.global_context thy;
    val ((_, def), thy') = Thm.add_def context unchecked overloaded (b, prop) thy;
    val thm = def
      |> Thm.forall_intr_frees
      |> Thm.forall_elim_vars 0
      |> Thm.varifyT_global;
  in yield_singleton (gen_add_thms (K I)) ((b, thm), atts) thy' end);

in

val add_defs = add false;
val add_defs_unchecked = add true;

end;

end;
