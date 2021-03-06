(*  Title:      Pure/Proof/reconstruct.ML
    Author:     Stefan Berghofer, TU Muenchen

Reconstruction of partial proof terms.
*)

signature RECONSTRUCT =
sig
  val quiet_mode : bool Config.T
  val reconstruct_proof : Proof.context -> term -> Proofterm.proof -> Proofterm.proof
  val prop_of' : term list -> Proofterm.proof -> term
  val prop_of : Proofterm.proof -> term
  val proof_of : Proof.context -> thm -> Proofterm.proof
  val expand_proof : Proof.context -> (string * term option) list ->
    Proofterm.proof -> Proofterm.proof
  val clean_proof_of : Proof.context -> bool -> thm -> Proofterm.proof
end;

structure Reconstruct : RECONSTRUCT =
struct

val quiet_mode =
  Config.bool (Config.declare ("Reconstruct.quiet_mode", \<^here>) (K (Config.Bool true)));

fun message ctxt msg =
  if Config.get ctxt quiet_mode then () else writeln (msg ());

fun vars_of t = map Var (rev (Term.add_vars t []));
fun frees_of t = map Free (rev (Term.add_frees t []));

fun forall_intr_vfs prop = fold_rev Logic.all
  (vars_of prop @ frees_of prop) prop;

fun forall_intr_vfs_prf prop prf = fold_rev Proofterm.forall_intr_proof'
  (vars_of prop @ frees_of prop) prf;


(**** generate constraints for proof term ****)

fun mk_var env Ts T =
  let val (env', v) = Envir.genvar "a" (env, rev Ts ---> T)
  in (list_comb (v, map Bound (length Ts - 1 downto 0)), env') end;

fun mk_tvar S (Envir.Envir {maxidx, tenv, tyenv}) =
  (TVar (("'t", maxidx + 1), S),
    Envir.Envir {maxidx = maxidx + 1, tenv = tenv, tyenv = tyenv});

val mk_abs = fold (fn T => fn u => Abs ("", T, u));

fun unifyT ctxt env T U =
  let
    val Envir.Envir {maxidx, tenv, tyenv} = env;
    val (tyenv', maxidx') = Sign.typ_unify (Proof_Context.theory_of ctxt) (T, U) (tyenv, maxidx);
  in Envir.Envir {maxidx = maxidx', tenv = tenv, tyenv = tyenv'} end;

fun chaseT env (T as TVar v) =
      (case Type.lookup (Envir.type_env env) v of
        NONE => T
      | SOME T' => chaseT env T')
  | chaseT _ T = T;

fun infer_type ctxt (env as Envir.Envir {maxidx, tenv, tyenv}) Ts vTs
      (t as Const (s, T)) = if T = dummyT then
        (case Sign.const_type (Proof_Context.theory_of ctxt) s of
          NONE => error ("reconstruct_proof: No such constant: " ^ quote s)
        | SOME T =>
            let val T' = Type.strip_sorts (Logic.incr_tvar (maxidx + 1) T)
            in (Const (s, T'), T', vTs,
              Envir.Envir {maxidx = maxidx + 1, tenv = tenv, tyenv = tyenv})
            end)
      else (t, T, vTs, env)
  | infer_type ctxt env Ts vTs (t as Free (s, T)) =
      if T = dummyT then (case Symtab.lookup vTs s of
          NONE =>
            let val (T, env') = mk_tvar [] env
            in (Free (s, T), T, Symtab.update_new (s, T) vTs, env') end
        | SOME T => (Free (s, T), T, vTs, env))
      else (t, T, vTs, env)
  | infer_type ctxt env Ts vTs (Var _) = error "reconstruct_proof: internal error"
  | infer_type ctxt env Ts vTs (Abs (s, T, t)) =
      let
        val (T', env') = if T = dummyT then mk_tvar [] env else (T, env);
        val (t', U, vTs', env'') = infer_type ctxt env' (T' :: Ts) vTs t
      in (Abs (s, T', t'), T' --> U, vTs', env'') end
  | infer_type ctxt env Ts vTs (t $ u) =
      let
        val (t', T, vTs1, env1) = infer_type ctxt env Ts vTs t;
        val (u', U, vTs2, env2) = infer_type ctxt env1 Ts vTs1 u;
      in (case chaseT env2 T of
          Type ("fun", [U', V]) => (t' $ u', V, vTs2, unifyT ctxt env2 U U')
        | _ =>
          let val (V, env3) = mk_tvar [] env2
          in (t' $ u', V, vTs2, unifyT ctxt env3 T (U --> V)) end)
      end
  | infer_type ctxt env Ts vTs (t as Bound i) = ((t, nth Ts i, vTs, env)
      handle General.Subscript => error ("infer_type: bad variable index " ^ string_of_int i));

fun cantunify ctxt (t, u) =
  error ("Non-unifiable terms:\n" ^
    Syntax.string_of_term ctxt t ^ "\n\n" ^ Syntax.string_of_term ctxt u);

fun decompose ctxt Ts (p as (t, u)) env =
  let
    fun rigrig (a, T) (b, U) uT ts us =
      if a <> b then cantunify ctxt p
      else apfst flat (fold_map (decompose ctxt Ts) (ts ~~ us) (uT env T U))
  in
    case apply2 (strip_comb o Envir.head_norm env) p of
      ((Const c, ts), (Const d, us)) => rigrig c d (unifyT ctxt) ts us
    | ((Free c, ts), (Free d, us)) => rigrig c d (unifyT ctxt) ts us
    | ((Bound i, ts), (Bound j, us)) =>
        rigrig (i, dummyT) (j, dummyT) (K o K) ts us
    | ((Abs (_, T, t), []), (Abs (_, U, u), [])) =>
        decompose ctxt (T::Ts) (t, u) (unifyT ctxt env T U)
    | ((Abs (_, T, t), []), _) =>
        decompose ctxt (T::Ts) (t, incr_boundvars 1 u $ Bound 0) env
    | (_, (Abs (_, T, u), [])) =>
        decompose ctxt (T::Ts) (incr_boundvars 1 t $ Bound 0, u) env
    | _ => ([(mk_abs Ts t, mk_abs Ts u)], env)
  end;

fun make_constraints_cprf ctxt env cprf =
  let
    fun add_cnstrt Ts prop prf cs env vTs (t, u) =
      let
        val t' = mk_abs Ts t;
        val u' = mk_abs Ts u
      in
        (prop, prf, cs, Pattern.unify (Context.Proof ctxt) (t', u') env, vTs)
        handle Pattern.Pattern =>
            let val (cs', env') = decompose ctxt [] (t', u') env
            in (prop, prf, cs @ cs', env', vTs) end
        | Pattern.Unif =>
            cantunify ctxt (Envir.norm_term env t', Envir.norm_term env u')
      end;

    fun mk_cnstrts_atom env vTs prop opTs prf =
          let
            val tvars = Term.add_tvars prop [] |> rev;
            val tfrees = Term.add_tfrees prop [] |> rev;
            val (Ts, env') =
              (case opTs of
                NONE => fold_map mk_tvar (map snd tvars @ map snd tfrees) env
              | SOME Ts => (Ts, env));
            val prop' = subst_atomic_types (map TVar tvars @ map TFree tfrees ~~ Ts)
              (forall_intr_vfs prop) handle ListPair.UnequalLengths =>
                error ("Wrong number of type arguments for " ^ quote (Proofterm.guess_name prf))
          in (prop', Proofterm.change_type (SOME Ts) prf, [], env', vTs) end;

    fun head_norm (prop, prf, cnstrts, env, vTs) =
      (Envir.head_norm env prop, prf, cnstrts, env, vTs);

    fun mk_cnstrts env _ Hs vTs (PBound i) = ((nth Hs i, PBound i, [], env, vTs)
          handle General.Subscript => error ("mk_cnstrts: bad variable index " ^ string_of_int i))
      | mk_cnstrts env Ts Hs vTs (Abst (s, opT, cprf)) =
          let
            val (T, env') =
              (case opT of
                NONE => mk_tvar [] env
              | SOME T => (T, env));
            val (t, prf, cnstrts, env'', vTs') =
              mk_cnstrts env' (T::Ts) (map (incr_boundvars 1) Hs) vTs cprf;
          in
            (Const ("Pure.all", (T --> propT) --> propT) $ Abs (s, T, t), Abst (s, SOME T, prf),
              cnstrts, env'', vTs')
          end
      | mk_cnstrts env Ts Hs vTs (AbsP (s, SOME t, cprf)) =
          let
            val (t', _, vTs', env') = infer_type ctxt env Ts vTs t;
            val (u, prf, cnstrts, env'', vTs'') = mk_cnstrts env' Ts (t'::Hs) vTs' cprf;
          in (Logic.mk_implies (t', u), AbsP (s, SOME t', prf), cnstrts, env'', vTs'')
          end
      | mk_cnstrts env Ts Hs vTs (AbsP (s, NONE, cprf)) =
          let
            val (t, env') = mk_var env Ts propT;
            val (u, prf, cnstrts, env'', vTs') = mk_cnstrts env' Ts (t::Hs) vTs cprf;
          in (Logic.mk_implies (t, u), AbsP (s, SOME t, prf), cnstrts, env'', vTs')
          end
      | mk_cnstrts env Ts Hs vTs (cprf1 %% cprf2) =
          let val (u, prf2, cnstrts, env', vTs') = mk_cnstrts env Ts Hs vTs cprf2
          in (case head_norm (mk_cnstrts env' Ts Hs vTs' cprf1) of
              (Const ("Pure.imp", _) $ u' $ t', prf1, cnstrts', env'', vTs'') =>
                add_cnstrt Ts t' (prf1 %% prf2) (cnstrts' @ cnstrts)
                  env'' vTs'' (u, u')
            | (t, prf1, cnstrts', env'', vTs'') =>
                let val (v, env''') = mk_var env'' Ts propT
                in add_cnstrt Ts v (prf1 %% prf2) (cnstrts' @ cnstrts)
                  env''' vTs'' (t, Logic.mk_implies (u, v))
                end)
          end
      | mk_cnstrts env Ts Hs vTs (cprf % SOME t) =
          let val (t', U, vTs1, env1) = infer_type ctxt env Ts vTs t
          in (case head_norm (mk_cnstrts env1 Ts Hs vTs1 cprf) of
             (Const ("Pure.all", Type ("fun", [Type ("fun", [T, _]), _])) $ f,
                 prf, cnstrts, env2, vTs2) =>
               let val env3 = unifyT ctxt env2 T U
               in (betapply (f, t'), prf % SOME t', cnstrts, env3, vTs2)
               end
           | (u, prf, cnstrts, env2, vTs2) =>
               let val (v, env3) = mk_var env2 Ts (U --> propT);
               in
                 add_cnstrt Ts (v $ t') (prf % SOME t') cnstrts env3 vTs2
                   (u, Const ("Pure.all", (U --> propT) --> propT) $ v)
               end)
          end
      | mk_cnstrts env Ts Hs vTs (cprf % NONE) =
          (case head_norm (mk_cnstrts env Ts Hs vTs cprf) of
             (Const ("Pure.all", Type ("fun", [Type ("fun", [T, _]), _])) $ f,
                 prf, cnstrts, env', vTs') =>
               let val (t, env'') = mk_var env' Ts T
               in (betapply (f, t), prf % SOME t, cnstrts, env'', vTs')
               end
           | (u, prf, cnstrts, env', vTs') =>
               let
                 val (T, env1) = mk_tvar [] env';
                 val (v, env2) = mk_var env1 Ts (T --> propT);
                 val (t, env3) = mk_var env2 Ts T
               in
                 add_cnstrt Ts (v $ t) (prf % SOME t) cnstrts env3 vTs'
                   (u, Const ("Pure.all", (T --> propT) --> propT) $ v)
               end)
      | mk_cnstrts env _ _ vTs (prf as PThm (_, ((_, prop, opTs), _))) =
          mk_cnstrts_atom env vTs prop opTs prf
      | mk_cnstrts env _ _ vTs (prf as PAxm (_, prop, opTs)) =
          mk_cnstrts_atom env vTs prop opTs prf
      | mk_cnstrts env _ _ vTs (prf as OfClass (T, c)) =
          mk_cnstrts_atom env vTs (Logic.mk_of_class (T, c)) NONE prf
      | mk_cnstrts env _ _ vTs (prf as Oracle (_, prop, opTs)) =
          mk_cnstrts_atom env vTs prop opTs prf
      | mk_cnstrts env _ _ vTs (Hyp t) = (t, Hyp t, [], env, vTs)
      | mk_cnstrts _ _ _ _ _ = error "reconstruct_proof: minimal proof object"
  in mk_cnstrts env [] [] Symtab.empty cprf end;


(**** update list of free variables of constraints ****)

fun upd_constrs env cs =
  let
    val tenv = Envir.term_env env;
    val tyenv = Envir.type_env env;
    val dom = []
      |> Vartab.fold (cons o #1) tenv
      |> Vartab.fold (cons o #1) tyenv;
    val vran = []
      |> Vartab.fold (Term.add_var_names o #2 o #2) tenv
      |> Vartab.fold (Term.add_tvar_namesT o #2 o #2) tyenv;
    fun check_cs [] = []
      | check_cs ((u, p, vs) :: ps) =
          let val vs' = subtract (op =) dom vs in
            if vs = vs' then (u, p, vs) :: check_cs ps
            else (true, p, fold (insert op =) vs' vran) :: check_cs ps
          end;
  in check_cs cs end;


(**** solution of constraints ****)

fun solve _ [] bigenv = bigenv
  | solve ctxt cs bigenv =
      let
        fun search env [] = error ("Unsolvable constraints:\n" ^
              Pretty.string_of (Pretty.chunks (map (fn (_, p, _) =>
                Thm.pretty_flexpair ctxt (apply2 (Envir.norm_term bigenv) p)) cs)))
          | search env ((u, p as (t1, t2), vs)::ps) =
              if u then
                let
                  val tn1 = Envir.norm_term bigenv t1;
                  val tn2 = Envir.norm_term bigenv t2
                in
                  if Pattern.pattern tn1 andalso Pattern.pattern tn2 then
                    (Pattern.unify (Context.Proof ctxt) (tn1, tn2) env, ps) handle Pattern.Unif =>
                       cantunify ctxt (tn1, tn2)
                  else
                    let val (cs', env') = decompose ctxt [] (tn1, tn2) env
                    in if cs' = [(tn1, tn2)] then
                         apsnd (cons (false, (tn1, tn2), vs)) (search env ps)
                       else search env' (map (fn q => (true, q, vs)) cs' @ ps)
                    end
                end
              else apsnd (cons (false, p, vs)) (search env ps);
        val Envir.Envir {maxidx, ...} = bigenv;
        val (env, cs') = search (Envir.empty maxidx) cs;
      in
        solve ctxt (upd_constrs env cs') (Envir.merge (bigenv, env))
      end;


(**** reconstruction of proofs ****)

fun reconstruct_proof ctxt prop cprf =
  let
    val (cprf' % SOME prop', thawf) = Proofterm.freeze_thaw_prf (cprf % SOME prop);
    val _ = message ctxt (fn _ => "Collecting constraints ...");
    val (t, prf, cs, env, _) = make_constraints_cprf ctxt
      (Envir.empty (Proofterm.maxidx_proof cprf ~1)) cprf';
    val cs' =
      map (apply2 (Envir.norm_term env)) ((t, prop') :: cs)
      |> map (fn p => (true, p, Term.add_var_names (#1 p) (Term.add_var_names (#2 p) [])));
    val _ =
      message ctxt
        (fn () => "Solving remaining constraints (" ^ string_of_int (length cs') ^ ") ...");
    val env' = solve ctxt cs' env
  in
    thawf (Proofterm.norm_proof env' prf)
  end;

fun prop_of_atom prop Ts = subst_atomic_types
  (map TVar (Term.add_tvars prop [] |> rev) @ map TFree (Term.add_tfrees prop [] |> rev) ~~ Ts)
  (forall_intr_vfs prop);

val head_norm = Envir.head_norm Envir.init;

fun prop_of0 Hs (PBound i) = nth Hs i
  | prop_of0 Hs (Abst (s, SOME T, prf)) =
      Logic.all_const T $ (Abs (s, T, prop_of0 Hs prf))
  | prop_of0 Hs (AbsP (s, SOME t, prf)) =
      Logic.mk_implies (t, prop_of0 (t :: Hs) prf)
  | prop_of0 Hs (prf % SOME t) = (case head_norm (prop_of0 Hs prf) of
      Const ("Pure.all", _) $ f => f $ t
    | _ => error "prop_of: all expected")
  | prop_of0 Hs (prf1 %% prf2) = (case head_norm (prop_of0 Hs prf1) of
      Const ("Pure.imp", _) $ P $ Q => Q
    | _ => error "prop_of: ==> expected")
  | prop_of0 Hs (Hyp t) = t
  | prop_of0 Hs (PThm (_, ((_, prop, SOME Ts), _))) = prop_of_atom prop Ts
  | prop_of0 Hs (PAxm (_, prop, SOME Ts)) = prop_of_atom prop Ts
  | prop_of0 Hs (OfClass (T, c)) = Logic.mk_of_class (T, c)
  | prop_of0 Hs (Oracle (_, prop, SOME Ts)) = prop_of_atom prop Ts
  | prop_of0 _ _ = error "prop_of: partial proof object";

val prop_of' = Envir.beta_eta_contract oo prop_of0;
val prop_of = prop_of' [];

fun proof_of ctxt raw_thm =
  let val thm = Thm.transfer' ctxt raw_thm
  in reconstruct_proof ctxt (Thm.prop_of thm) (Thm.proof_of thm) end;



(**** expand and reconstruct subproofs ****)

fun expand_proof ctxt thms prf =
  let
    fun expand maxidx prfs (AbsP (s, t, prf)) =
          let val (maxidx', prfs', prf') = expand maxidx prfs prf
          in (maxidx', prfs', AbsP (s, t, prf')) end
      | expand maxidx prfs (Abst (s, T, prf)) =
          let val (maxidx', prfs', prf') = expand maxidx prfs prf
          in (maxidx', prfs', Abst (s, T, prf')) end
      | expand maxidx prfs (prf1 %% prf2) =
          let
            val (maxidx', prfs', prf1') = expand maxidx prfs prf1;
            val (maxidx'', prfs'', prf2') = expand maxidx' prfs' prf2;
          in (maxidx'', prfs'', prf1' %% prf2') end
      | expand maxidx prfs (prf % t) =
          let val (maxidx', prfs', prf') = expand maxidx prfs prf
          in (maxidx', prfs', prf' % t) end
      | expand maxidx prfs (prf as PThm (_, ((a, prop, SOME Ts), body))) =
          if not (exists
            (fn (b, NONE) => a = b
              | (b, SOME prop') => a = b andalso prop = prop') thms)
          then (maxidx, prfs, prf) else
          let
            val (maxidx', prf, prfs') =
              (case AList.lookup (op =) prfs (a, prop) of
                NONE =>
                  let
                    val _ =
                      message ctxt (fn () =>
                        "Reconstructing proof of " ^ a ^ "\n" ^ Syntax.string_of_term ctxt prop);
                    val prf' = forall_intr_vfs_prf prop
                      (reconstruct_proof ctxt prop (Proofterm.join_proof body));
                    val (maxidx', prfs', prf) = expand
                      (Proofterm.maxidx_proof prf' ~1) prfs prf'
                  in (maxidx' + maxidx + 1, Proofterm.incr_indexes (maxidx + 1) prf,
                    ((a, prop), (maxidx', prf)) :: prfs')
                  end
              | SOME (maxidx', prf) => (maxidx' + maxidx + 1,
                  Proofterm.incr_indexes (maxidx + 1) prf, prfs));
            val tfrees = Term.add_tfrees prop [] |> rev;
            val tye = map (fn ((s, j), _) => (s, maxidx + 1 + j))
              (Term.add_tvars prop [] |> rev) @ map (rpair ~1 o fst) tfrees ~~ Ts;
            val varify = map_type_tfree (fn p as (a, S) =>
              if member (op =) tfrees p then TVar ((a, ~1), S) else TFree p)
          in
            (maxidx', prfs', Proofterm.map_proof_types (typ_subst_TVars tye o varify) prf)
          end
      | expand maxidx prfs prf = (maxidx, prfs, prf);

  in #3 (expand (Proofterm.maxidx_proof prf ~1) [] prf) end;


(* cleanup for output etc. *)

fun clean_proof_of ctxt full thm =
  let
    val (_, prop) =
      Logic.unconstrainT (Thm.shyps_of thm)
        (Logic.list_implies (Thm.hyps_of thm, Thm.prop_of thm));
  in
    Proofterm.proof_of (Proofterm.strip_thm (Thm.proof_body_of thm))
    |> reconstruct_proof ctxt prop
    |> expand_proof ctxt [("", NONE)]
    |> Proofterm.rew_proof (Proof_Context.theory_of ctxt)
    |> Proofterm.no_thm_proofs
    |> not full ? Proofterm.shrink_proof
  end;

end;
