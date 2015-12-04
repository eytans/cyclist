open Lib
open Util
open Extended_while_program

module SH = Sl_heap

exception Not_symheap = Sl_form.Not_symheap

module Rule = Proofrule.Make(Extended_while_program.Seq)
module Seqtactics = Seqtactics.Make(Extended_while_program.Seq)
module Proof = Proof.Make(Extended_while_program.Seq)
module Slprover = Prover.Make(Sl_seq)

(* Wrapper for the entailment prover *)
let entails f f' =
  Slprover.idfs 1 Sl_abduce.max_depth !Sl_rules.axioms !Sl_rules.rules (f, f')

let tagpairs = Seq.tag_pairs

(* following is for symex only *)
let progpairs tps = 
  if !termination then tps else Seq.tagpairs_one

let dest_sh_seq (pre, cmd, post) = (Sl_form.dest pre, cmd, post)


(* axioms *)

(* If the precondition of the candidate sequence is inconsistent, then we can *)
(* close it of as instance of the Ex Falso axiom *)
let ex_falso_axiom = 
  Rule.mk_axiom (
    fun (pre, _, _) -> 
      Option.mk (Sl_form.inconsistent pre) "Ex Falso")

(* If the precondition entails the post condition and the command is stop, *)
(* then we can apply the Stop axiom. *)
let mk_symex_stop_axiom =
  Rule.mk_axiom (
    fun (pre, cmd, post) ->
      Option.mk (Cmd.is_stop cmd && Option.is_some (entails pre post)) "Stop")

(* If the precondition entails the post condition and the command list is empty, *)
(* then we can apply the Stop axiom. *)
let mk_symex_empty_axiom =
  Rule.mk_axiom (
    fun (pre, cmd, post) -> 
      Option.mk (Cmd.is_empty cmd && Option.is_some (entails pre post)) "Empty")

(* simplification rules *)

(* Tactic which tries to simplify the sequent by replacing existential variables *)
(* in the precondition and fails if no such replacements can be made *)
(* TODO: ?make a similar simplification tactic that replaces existentials in postcondition *)
let eq_subst_ex_f ((pre, cmd, post) as s) =
  let pre' = Sl_form.subst_existentials pre in
  if Sl_form.equal pre pre' then [] else
  [ [ ((pre', cmd, post), tagpairs s, TagPairs.empty) ], "Eq. subst. ex" ]

(* Tactic which tried to simplify the sequent by normalising: that is, using the *)
(* equalities in the formula as a substitution for the disequality, points-to and *)
(* predicate subformulae *)
(* TODO: ?make a similar simplification tactic that normalises the postcondition *)
(* let norm ((pre ,cmd, post) as s) =                                *)
(*   let pre' = Sl_form.norm pre in                                  *)
(*   if Sl_form.equal pre pre' then [] else                          *)
(*   [ [( (pre', cmd, post), tagpairs s, TagPairs.empty)], "Norm" ]  *)

let simplify_rules = [ eq_subst_ex_f ]

(* Tactic which performs as many simplifications as possible all in one go *)
let simplify_seq_rl = 
  Seqtactics.relabel "Simplify" 
    (Seqtactics.repeat (Seqtactics.first simplify_rules))
    
let simplify = Rule.mk_infrule simplify_seq_rl  

(* Function which takes a tactic, composes it with a general simplification attempt *)
(* tactic, and creates a compound inference rule out of it *)
let wrap r =
  Rule.mk_infrule
    (Seqtactics.compose r (Seqtactics.attempt simplify_seq_rl))


(* break LHS disjunctions *)
let lhs_disj_to_symheaps =
  let rl ((_, hs) as pre, cmd, post) =
    if Blist.length hs < 2 then [] else
    [ Blist.map 
        (fun h -> 
          let s' = ((Sl_form.with_heaps pre [h]), cmd, post) in 
          (s', tagpairs s', TagPairs.empty ) ) 
        hs,
      "L.Or"
    ] in
  Rule.mk_infrule rl

(* let gen_left_rules_f (def, ident) seq =                                                *)
(*   try                                                                                  *)
(*     let (pre, cmd, post) = dest_sh_seq seq in                                          *)
(*     let preds =                                                                        *)
(*       Sl_tpreds.filter (fun (_,(ident',_)) -> Strng.equal ident ident') pre.SH.inds in *)
(*     if Sl_tpreds.is_empty preds then [] else                                           *)
(*     let left_unfold ((id,(_,pvs)) as p) =                                              *)
(*       let ts = Tags.inter (Sl_heap.tags pre) (Sl_heap.tags pre) in                     *)
(*       let pre' = SH.del_ind pre p in                                                   *)
(*       let do_case case =                                                               *)
(*         let n = Blist.length (Sl_indrule.formals case) in                              *)
(*         let n' = Blist.length pvs in                                                   *)
(*         let err_msg = fun () ->                                                        *)
(*           (Printf.sprintf                                                              *)
(*             "Skipping unfolding of inductive predicate \"%s\" \                        *)
(*             due to parameter mismatch: definition expects %d parameters, \             *)
(*             but was given %d" ident n n')  in                                          *)
(*         Option.mk_lazily (n == n' || (debug err_msg; false))                           *)
(*         (fun () ->                                                                     *)
(*           let (f', (_,vs')) = Sl_indrule.dest (freshen_case_by_seq seq case) in        *)
(*           let theta = Sl_term.Map.of_list (Blist.combine vs' pvs) in                   *)
(*           let f' = Sl_heap.subst theta f' in                                           *)
(*           let f' = Sl_heap.repl_tags id f' in                                          *)
(*           let pre' = Sl_heap.star pre' f' in                                           *)
(*           (                                                                            *)
(*             ([pre'], cmd, post),                                                       *)
(*             (if !termination then TagPairs.mk ts else Seq.tagpairs_one),               *)
(*             (if !termination then TagPairs.singleton (id,id) else TagPairs.empty)      *)
(*           )) in                                                                        *)
(*       let subgoals = Option.list_get (Blist.map do_case def) in                        *)
(*       Option.mk (not (Blist.is_empty subgoals)) (subgoals, (ident ^ " L.Unf.")) in     *)
(*     Option.list_get (Sl_tpreds.map_to_list left_unfold preds)                          *)
(*   with Not_symheap -> []                                                               *)
 
(* let gen_left_rules (def,ident) =                                                       *)
(*   wrap (gen_left_rules_f (def,ident))                                                  *)

let luf_rl defs ((pre,cmd,post) as seq) =
  try
    let (cs, pre) = Sl_form.dest pre in
    let seq_vars = Seq.vars seq in
    let seq_tags = Seq.all_tags seq in
    let left_unfold ((tag, (ident, _)) as p) = 
      let pre' = Sl_heap.del_ind pre p in
      let cases = Sl_defs.unfold (seq_vars, seq_tags) p defs in
      let do_case f =
        let new_cs = 
          Ord_constraints.union cs 
            (Ord_constraints.generate tag (Sl_heap.tags f)) in
        let cclosure = Ord_constraints.close new_cs in
        let (vts, pts) = 
          let collect tps = TagPairs.endomap Pair.swap
            (TagPairs.filter (fun (_, t) -> Tags.mem t seq_tags) tps) in
          Pair.map collect 
            (Ord_constraints.all_pairs cclosure, 
              Ord_constraints.prog_pairs cclosure) in
        let vts = TagPairs.union vts (TagPairs.mk (Sl_heap.tags pre')) in
        ( 
          ((new_cs, [Sl_heap.star pre' f]), cmd, post), 
          (if !termination then vts else Seq.tagpairs_one), 
          (if !termination then pts else TagPairs.empty)
        ) in
      let () = debug (fun () -> "L. Unfolding " ^ (Sl_predsym.to_string ident)) in 
      Blist.map do_case cases, ((Sl_predsym.to_string ident) ^ " L.Unf.") in
    Sl_tpreds.map_to_list 
      left_unfold 
      (Sl_tpreds.filter (Sl_defs.is_defined defs) pre.SH.inds)
  with Not_symheap -> []

let luf defs = wrap (luf_rl defs)

let ruf_rl defs ((pre,cmd,post) as seq) =
  let (cs, h) = Sl_form.dest post in
  let seq_vars = Seq.vars seq in
  let seq_tags = Seq.all_tags seq in
  let preds = Sl_tpreds.filter (Sl_defs.is_defined defs) h.SH.inds in 
  let right_unfold ((tag, (ident, _)) as p) =
    let h' = SH.del_ind h p in
    let clauses = Sl_defs.unfold (seq_vars, seq_tags) p defs in
    let do_case f =
      let cs' = 
        Ord_constraints.union cs 
          (Ord_constraints.generate tag (Sl_heap.tags f)) in
      let h' = Sl_heap.star h' f in
      let seq' = (pre, cmd, (cs', [h'])) in
        [ (seq', tagpairs seq', TagPairs.empty) ],
        (Sl_predsym.to_string ident) ^ " R.Unf."
      in
    let () = debug (fun () -> "R. Unfolding " ^ (Sl_predsym.to_string ident)) in 
    Blist.map do_case clauses in
  Blist.flatten (Sl_tpreds.map_to_list right_unfold preds)

let ruf defs = wrap (ruf_rl defs)

(* FOR SYMEX ONLY *)
let fix_tps l = 
  Blist.map 
    (fun (g,d) -> 
      Blist.map 
        (fun s -> (s, tagpairs s, progpairs TagPairs.empty )) g, 
        d) 
    l 

let mk_symex f = 
  let rl ((pre, cmd, post) as seq) =
    if (Cmd.is_empty cmd) then
      []
    else
      let cont = Cmd.get_cont cmd in
      fix_tps 
        (Blist.map 
          (fun (g,d) -> 
            (Blist.map 
              (fun h' -> ((Sl_form.with_heaps pre [h']), cont, post)) g),
            d) 
          (f seq)) in
  wrap rl
  
(* symbolic execution rules *)
let symex_assign_rule =
  let rl ((pre, cmd, _) as seq) =
    try
      let (_, h) = Sl_form.dest pre in
      let (x,e) = Cmd.dest_assign cmd in
      let fv = fresh_evar (Seq.vars seq) in
      let theta = Sl_term.singleton_subst x fv in
      let h' = Sl_heap.subst theta h in
      let e' = Sl_term.subst theta e in
      [[ SH.add_eq h' (e', x) ], "Assign"]
    with WrongCmd | Not_symheap -> [] in
  mk_symex rl

let find_pto_on f e = 
  Sl_ptos.find (fun (l,_) -> Sl_heap.equates f e l) f.SH.ptos
  
let symex_load_rule =
  let rl ((pre, cmd, _) as seq) =
    try
      let (_, h) = Sl_form.dest pre in
      let (x,e,f) = Cmd.dest_load cmd in
      let (_,ys) = find_pto_on h e in
      let t = Blist.nth ys (Field.get_index f) in
      let fv = fresh_evar (Seq.vars seq) in
      let theta = Sl_term.singleton_subst x fv in
      let h' = Sl_heap.subst theta h in
      let t' = Sl_term.subst theta t in
      [[ SH.add_eq h' (t',x) ], "Load"]
    with Not_symheap | WrongCmd | Not_found -> [] in
  mk_symex rl

let symex_store_rule =
  let rl (pre, cmd, _) =
    try
      let (_, h) = Sl_form.dest pre in
      let (x,f,e) = Cmd.dest_store cmd in
      let ((x',ys) as pto) = find_pto_on h x in
      let pto' = (x', Blist.replace_nth e (Field.get_index f) ys) in
      [[ SH.add_pto (SH.del_pto h pto) pto' ], "Store"]
    with Not_symheap | WrongCmd | Not_found -> [] in
  mk_symex rl

let symex_free_rule =
  let rl (pre, cmd, _) =
    try
      let (_, h) = Sl_form.dest pre in
      let e = Cmd.dest_free cmd in
      let pto = find_pto_on h e in
      [[ SH.del_pto h pto ], "Free"]
    with Not_symheap | WrongCmd | Not_found -> [] in
  mk_symex rl

let symex_new_rule =
  let rl ((pre, cmd, _) as seq) =
    try
      let (_, h) = Sl_form.dest pre in
      let x = Cmd.dest_new cmd in
      let l = fresh_evars (Seq.vars seq) (1 + (Field.get_no_fields ())) in
      let (fv,fvs) = (Blist.hd l, Blist.tl l) in
      let h' = Sl_heap.subst (Sl_term.singleton_subst x fv) h in
      let new_pto = Sl_heap.mk_pto (x, fvs) in
      [[ Sl_heap.star h' new_pto ], "New"]
    with Not_symheap | WrongCmd -> [] in
  mk_symex rl

let symex_skip_rule =
  let rl (pre, cmd, _) =
    try
      let (_, h) = Sl_form.dest pre in
      let () = Cmd.dest_skip cmd in [[h], "Skip"]
    with Not_symheap | WrongCmd -> [] in
  mk_symex rl

let symex_if_rule =
  let rl (pre, cmd, post) =
    try
      let (_, h) = Sl_form.dest pre in
      let (c,cmd') = Cmd.dest_if cmd in
      let cont = Cmd.get_cont cmd in
      let (cond_true, cond_false) = Cond.fork h c in 
      fix_tps 
        [
          [ ((Sl_form.with_heaps pre [cond_true]), Cmd.mk_seq cmd' cont, post) ; 
            ((Sl_form.with_heaps pre [cond_false]), cont, post) ], 
          "If"
        ]
    with Not_symheap | WrongCmd -> [] in
  wrap rl

let symex_ifelse_rule =
  let rl (pre, cmd, post) =
    try
      let (_, h) = Sl_form.dest pre in
      let (c,cmd1,cmd2) = Cmd.dest_ifelse cmd in
      let cont = Cmd.get_cont cmd in
      let (cond_true, cond_false) = Cond.fork h c in 
      fix_tps 
        [
          [ ((Sl_form.with_heaps pre [cond_true]), Cmd.mk_seq cmd1 cont, post) ; 
            ((Sl_form.with_heaps pre [cond_false]), Cmd.mk_seq cmd2 cont, post) ],
         "IfElse"
        ]
    with Not_symheap | WrongCmd -> [] in
  wrap rl

let symex_while_rule =
  let rl (pre, cmd, post) =
    try
      let (_, h) = Sl_form.dest pre in
      let (c,cmd') = Cmd.dest_while cmd in
      let cont = Cmd.get_cont cmd in
      let (cond_true, cond_false) = Cond.fork h c in 
      fix_tps 
        [
          [ ((Sl_form.with_heaps pre [cond_true]), Cmd.mk_seq cmd' cmd, post) ; 
            ((Sl_form.with_heaps pre [cond_false]), cont, post) ], 
          "While"
        ]
    with Not_symheap | WrongCmd -> [] in
  wrap rl
  
let mk_symex_proc_unfold procs = 
  let rl (pre, cmd, post) = 
    try
      let (p, args) = Cmd.dest_proc_call cmd in
      if Cmd.is_empty (Cmd.get_cont cmd) then
        let (_,_,_,_, body) = Blist.find
          (fun (id, params, pre', post', _) -> 
            try
            id=p 
              && Blist.equal Sl_term.equal args params
              && Sl_form.equal pre pre'
              && Sl_form.equal post post'
            with Invalid_argument(_) -> false )
          (procs) in
        fix_tps [ [ (pre, body, post) ], "Proc Unf. " ^ p  ]
      else []
    with WrongCmd | Not_found -> [] in
  Rule.mk_infrule rl

let param_subst_rule theta ((_,cmd',_) as seq') ((_,cmd,_) as seq) =
  if Cmd.is_proc_call cmd && Cmd.is_empty (Cmd.get_cont cmd)
      && Cmd.is_proc_call cmd' && Cmd.is_empty (Cmd.get_cont cmd')
      && Seq.equal (Seq.param_subst theta seq') seq
    then 
      [ [(seq', Seq.tag_pairs seq', TagPairs.empty)], 
          "Param Subst" (* ^ (Format.asprintf " %a" Sl_term.pp_subst theta) *) ]
    else 
      []

let subst_rule (theta, tps) ((pre', _, _) as seq') ((pre, _, _) as seq) = 
  if Seq.equal seq (Seq.subst_tags tps (Seq.subst theta seq')) then
    let tagpairs () =
      if !termination then
        let tagpairs = TagPairs.filter
          (fun (t, t') -> 
            (Tags.mem t' (Sl_form.tags pre')) && (Tags.mem t (Sl_form.tags pre)))
          (TagPairs.reflect tps) in
        let unmapped = Tags.diff (Sl_form.tags pre) (TagPairs.projectl tagpairs) in
        let remaining = Tags.inter unmapped (Sl_form.tags pre') in
        TagPairs.union tagpairs (TagPairs.mk remaining)
      else Seq.tagpairs_one in
    [ [(seq', tagpairs(), TagPairs.empty)], 
        "Subst" (* ^ (Format.asprintf " %a" Sl_term.pp_subst theta) *) ]
  else 
    let () = debug (fun _ -> "Unsuccessfully tried to apply substitution rule!") in
    []

let left_or_elim_rule (((_, hs'),cmd',post') as seq') (pre,cmd,post) =
  try
    if Cmd.equal cmd cmd' && Sl_form.equal post post'
        && let (_, h) = Sl_form.dest pre in
           Blist.exists (Sl_heap.equal h) hs'
      then
        [ [(seq', Seq.tag_pairs seq', TagPairs.empty)], "L. Cut (Or Elim.)" ]
      else
        let () = debug (fun _ -> "Unsuccessfully tried to apply left_or_elim rule!") in
        []
  with Not_symheap -> []
      
(* Rule specialising/splitting existential variables on LHS *)
let ex_sp_left_rule ((pre, cmd, _) as seq) ((pre', cmd', _) as seq') =
  try
    let (pre_cs, pre_f) = Sl_form.dest pre in
    let (pre_cs', pre_f') = Sl_form.dest pre' in
    if not (Cmd.equal cmd cmd') then [] else
      let theta = Sl_unify.Unidirectional.realize 
        (Sl_heap.classical_unify 
          ~update_check:Sl_unify.Unidirectional.existentials_only
          pre_f pre_f'
        (Sl_unify.Unidirectional.unify_tag_constraints 
          ~total:true ~update_check:Sl_unify.Unidirectional.existentials_only
          pre_cs pre_cs'
        (Sl_unify.Unidirectional.mk_verifier 
          Sl_unify.Unidirectional.existential_split_check))) in 
      if Option.is_some theta then
        let tagpairs =
          if !termination then TagPairs.reflect (snd (Option.get theta))
          else Seq.tagpairs_one in 
        [ [(seq, tagpairs, TagPairs.empty)], "Cut (Ex. Sp.)" ]      
      else
        let () = debug (fun _ -> "Failed Ex. Sp. Check:\n\t" ^ (Seq.to_string seq) ^ "\n\t" ^ (Seq.to_string seq')) in
        []
  with Not_symheap -> []
      
let left_cut_rule ((pre, cmd, post) as seq) ((pre', cmd', post') as seq') =
  if Cmd.equal cmd cmd' && Sl_form.equal post post' 
      && Option.is_some (entails pre' pre) then
    let (valid, progressing) = 
      if !termination then Seq.get_tracepairs seq' seq 
      else (Seq.tagpairs_one, TagPairs.empty) in
    [ [ (seq, valid, progressing) ], "LHS.Conseq" ]
  else
    let () = debug (fun _ -> "Unsuccessfully tried to apply left cut rule!") in
    []
      
let right_cut_rule ((pre, cmd, post) as seq) (pre', cmd', post') =
  if Cmd.equal cmd cmd' && Sl_form.equal pre pre' 
      && Option.is_some (entails post post') then
    [ [ (seq, Seq.tag_pairs seq, TagPairs.empty) ], "RHS.Conseq" ]
  else
    let () = debug (fun _ -> "Unsuccessfully tried to apply right cut rule!") in
    []
    
let ex_intro_rule ((pre, cmd, _) as seq) ((pre', cmd', _) as seq') =
  if Cmd.equal cmd cmd' then
    try
      let (cs, h) = Sl_form.dest pre in
      let (cs', h') = Sl_form.dest pre' in
      let () = debug (fun _ -> "Testing existential introduction for:\n\t" ^ (Seq.to_string seq) ^ "\n\t" ^ (Seq.to_string seq')) in
      let update_check = 
        (fun ((_, (trm_subst, tag_subst)) as state_update) ->
          let () = debug (fun _ -> "\tTesting state update:" ^ 
            "\n\t\tTerms: " ^ (Sl_term.Map.to_string Sl_term.to_string trm_subst) ^
            "\n\t\tTags: " ^ (Strng.Pairing.Set.to_string (TagPairs.to_names tag_subst))) in
          let result =
            (Sl_unify.Unidirectional.existential_intro 
              (Sl_form.vars pre', Sl_form.tags pre')) state_update in
          let () = debug (fun _ -> "\tResult: " ^ (string_of_bool result)) in
          result) in
      let subst =
        Sl_unify.Unidirectional.realize
          (Sl_unify.Unidirectional.unify_tag_constraints 
            ~total:true ~inverse:true ~update_check
            cs cs'
          (Sl_heap.classical_unify ~inverse:true ~update_check h h'
          (Unification.trivial_continuation))) in
      if Option.is_some subst then
        let (_, tag_subst) = Option.get subst in
        let tps = 
          if !termination then
            TagPairs.union
              (TagPairs.mk (Tags.inter (Sl_form.tags pre) (Sl_form.tags pre')))
              tag_subst
          else Seq.tagpairs_one in
        [ [ seq, tps, TagPairs.empty ], "Ex.Intro." ]
      else
        let () = debug (fun _ -> "Unsuccessfully tried to apply the existential introduction rule!") in
        []
    with Not_symheap ->
      let () = debug (fun _ -> "Unsuccessfully tried to apply the existential introduction rule - something was not a symbolic heap!") in
      []
  else
    let () = debug (fun _ -> "Unsuccessfully tried to apply the existential introduction rule - commands not equal!") in
    []
      
let seq_rule mid ((pre, cmd, post) as src_seq) =
  try
    let (cmd, cont) = Cmd.split cmd in
    let left_seq = (pre, cmd, mid) in
    let right_seq = (mid, cmd, post) in
    let (allpairs, progressing) = 
      if !termination then Seq.get_tracepairs src_seq right_seq
      else (Seq.tagpairs_one, TagPairs.empty) in 
    [ [ (left_seq, tagpairs left_seq, TagPairs.empty) ;
        (right_seq, allpairs, progressing) ], "Seq." ]
  with WrongCmd -> 
    let () = debug (fun _ -> "Unsuccessfully tried to apply sequence rule - either command or continuation was empty!") in
    []
    
let frame_rule frame ((pre, cmd, post) as seq) ((pre', cmd', post') as seq') =
  if Cmd.equal cmd cmd' && Seq.equal (Seq.frame frame seq) seq' &&
     (Sl_term.Set.is_empty
       (Sl_term.Set.inter
         (Cmd.modifies ~strict:false cmd) 
         (Sl_form.vars frame)))
  then
    [ [ (seq, Seq.tag_pairs seq, TagPairs.empty) ], "Frame" ]
  else
    let () = debug (fun _ -> "Unsuccessfully tried to apply frame rule!") in
    []
      
let transform_seq ((pre, cmd, post) as seq) = 
  fun ?(match_post=true) ((pre', cmd', post') as seq') ->
    if not (Cmd.equal cmd cmd') then Blist.empty else
    if (Sl_form.equal pre pre') && (Sl_form.equal post post') then
      [ (seq, Rule.identity) ] else
    let () = debug (fun _ -> "Trying to unify left-hand sides of:" ^ "\n\tbud:" ^
      (Seq.to_string seq) ^ "\n\tcandidate companion: " ^ (Seq.to_string seq')) in
    let prog_vars = Cmd.vars cmd in
    let u_tag_theta = 
      TagPairs.mk_univ_subst
        (Tags.union (Seq.all_tags seq) (Seq.all_tags seq'))
        (Tags.filter Tags.is_exist_var (Sl_form.tags pre)) in
    let u_trm_theta =
      Sl_term.mk_univ_subst
        (Sl_term.Set.union (Seq.all_vars seq) (Seq.all_vars seq'))
        (Sl_term.Set.filter Sl_term.is_exist_var (Sl_form.vars pre)) in
    let upre =
      Sl_form.subst_tags u_tag_theta (Sl_form.subst u_trm_theta pre) in 
    let () = debug (fun _ -> "Instantiated existentials in bud precondition:" ^
      "\n\t" ^ (Sl_form.to_string upre) ^
      "\n\ttag subst: " ^ (Strng.Pairing.Set.to_string (TagPairs.to_names u_tag_theta)) ^
      "\n\tvar subst: " ^ (Sl_term.Map.to_string Sl_term.to_string u_trm_theta)) in
    let pre_transforms =
      Sl_abduce.abd_substs
        ~update_check:
          (Fun.disj
            (Sl_unify.Unidirectional.modulo_entl)
            (Fun.conj
              (Sl_unify.Unidirectional.is_substitution)
              (Sl_unify.Unidirectional.avoid_replacing_trms prog_vars)))
        upre pre' in
    let pre_transforms = 
      Option.map 
        (fun (interpolant, substs) -> 
          (interpolant, Sl_unify.Unidirectional.remove_dup_substs substs))
        pre_transforms in
    let mk_transform (g, g') (trm_subst, tag_subst) =
      let () = debug (fun _ -> "Found interpolant: (" ^ (Sl_form.to_string g) ^ ", " ^ (Sl_form.to_string g') ^ ")") in
      let () = debug (fun _ -> "Term sub: " ^ (Sl_term.Map.to_string Sl_term.to_string trm_subst)) in
      let () = debug (fun _ -> "Tag sub: " ^ (Strng.Pairing.Set.to_string (TagPairs.to_names tag_subst))) in
      let f = Sl_form.subst trm_subst (Sl_form.subst_tags tag_subst g') in
      let (trm_theta, trm_subst) = Sl_term.partition_subst trm_subst in
      let (tag_theta, tag_subst) = TagPairs.partition_subst tag_subst in
      let f' = Sl_form.subst trm_theta (Sl_form.subst_tags tag_theta post') in
      let used_tags = Tags.union (Sl_form.tags f) (Sl_form.tags f') in
      let used_trms = Sl_term.Set.union (Sl_form.vars f) (Sl_form.vars f') in
      let () = debug (fun _ -> "Computing frame left over from: " ^ (Sl_form.to_string f)) in
      let frame = Sl_form.compute_frame ~avoid:(used_tags, used_trms) f g in
      assert (Option.is_some frame) ;
      let frame = Option.get frame in
      let clashing_prog_vars =
        Sl_term.Set.inter (Cmd.modifies ~strict:false cmd) (Sl_form.vars frame) in
      let ex_subst = 
        Sl_term.mk_ex_subst 
          (Sl_term.Set.union used_trms (Sl_form.vars frame)) 
          clashing_prog_vars in
      let frame = Sl_form.subst ex_subst frame in 
      let () = debug (fun _ -> "Computed frame: " ^ (Sl_form.to_string frame)) in
      let framed_post = Sl_form.star ~augment_deqs:false f' frame in
      let () = debug (fun _ -> "Companion postcondition after substitution and framing: " ^ (Sl_form.to_string framed_post)) in
      let clashing_utags =
        Tags.inter
          (TagPairs.map_to Tags.add Tags.empty snd u_tag_theta)
          (Sl_form.tags framed_post) in
      let clashing_uvars = 
        Sl_term.Set.inter
          (Sl_term.Set.of_list (Blist.map snd (Sl_term.Map.bindings u_trm_theta)))
          (Sl_form.vars framed_post) in
      let post_tag_subst =
        TagPairs.mk_ex_subst
          (Tags.union (Sl_form.tags framed_post) (Sl_form.tags post))
          clashing_utags in
      let post_trm_subst = 
        Sl_term.mk_ex_subst
          (Sl_term.Set.union (Sl_form.vars framed_post) (Sl_form.vars post))
          clashing_uvars in
      let ex_post = 
        Sl_form.subst_tags 
          post_tag_subst 
          (Sl_form.subst post_trm_subst framed_post) in
      let post_transforms =
        if match_post then
          Sl_abduce.abd_bi_substs
            ~allow_frame:false
            ~update_check:
              (Fun.conj
                (Sl_unify.Bidirectional.updchk_inj_left
                  (Fun.conj
                    (Sl_unify.Unidirectional.is_substitution)
                    (Sl_unify.Unidirectional.avoid_replacing_trms 
                      (Sl_term.Set.union prog_vars (Sl_form.vars frame)))))
                (Sl_unify.Bidirectional.updchk_inj_right
                  Sl_unify.Unidirectional.modulo_entl))
            ex_post post
        else Some ((ex_post, post), [Sl_unify.Bidirectional.empty_state]) in
      Option.map
        (fun (_, substs) -> 
          (* We just need one, since it does not affect subsequent proof search *)
          let subst = Blist.hd substs in 
          let theta = fst subst in
          let () = debug (fun _ -> "Left-hand sub:") in
          let () = debug (fun _ -> "\tterms: " ^ (Sl_term.Map.to_string Sl_term.to_string (fst (fst subst)))) in
          let () = debug (fun _ -> "\ttags: " ^ (Strng.Pairing.Set.to_string (TagPairs.to_names (snd (fst subst))))) in
          let () = debug (fun _ -> "Right-hand sub:") in
          let () = debug (fun _ -> "\tterms: " ^ (Sl_term.Map.to_string Sl_term.to_string (fst (snd subst)))) in
          let () = debug (fun _ -> "\ttags: " ^ (Strng.Pairing.Set.to_string (TagPairs.to_names (snd (snd subst))))) in
          let trm_theta = Sl_term.Map.union trm_theta (Sl_term.strip_subst (fst theta)) in
          let tag_theta = TagPairs.union tag_theta (TagPairs.strip (snd theta)) in
          let () = debug (fun _ -> "Verified entailment with bud postcondition") in
          let () = debug (fun _ -> "Added term substitution: " ^ (Sl_term.Map.to_string Sl_term.to_string trm_theta)) in
          let () = debug (fun _ -> "Added tag substitution: " ^ (Strng.Pairing.Set.to_string (TagPairs.to_names tag_theta))) in
          let subst_seq = Seq.subst_tags tag_theta (Seq.subst trm_theta seq') in
          let interpolated_seq = (f, cmd, f') in
          let framed_seq = 
            let framed_pre = Sl_form.star ~augment_deqs:false frame f in
            (framed_pre, cmd, framed_post) in
          let univ_seq = Seq.with_pre framed_seq g in
          let partial_univ_seq = Seq.with_post univ_seq ex_post in
          let ex_seq = Seq.with_pre partial_univ_seq pre in
          let rule =
            Rule.sequence [
                if (not match_post) || Seq.equal seq ex_seq
                  then Rule.identity
                  else Rule.mk_infrule (right_cut_rule ex_seq) ;
                
                if Seq.equal ex_seq partial_univ_seq
                  then Rule.identity
                  else Rule.mk_infrule (ex_intro_rule partial_univ_seq) ;
                  
                if Seq.equal partial_univ_seq univ_seq
                  then Rule.identity
                  else Rule.mk_infrule (right_cut_rule univ_seq) ;
                  
                if Seq.equal univ_seq framed_seq
                  then Rule.identity
                  else Rule.mk_infrule (left_cut_rule framed_seq) ;
                  
                if Seq.equal framed_seq interpolated_seq
                  then Rule.identity
                  else Rule.mk_infrule (frame_rule frame interpolated_seq) ;
                  
                if Seq.equal interpolated_seq subst_seq
                  then Rule.identity
                  else Rule.mk_infrule (left_cut_rule subst_seq) ;
                  
                if Seq.equal subst_seq seq'
                  then Rule.identity
                  else Rule.mk_infrule (subst_rule (trm_theta, tag_theta) seq') ;
              ] in
            ((if match_post then seq else ex_seq), rule))
        post_transforms in
    let result = Option.dest
      Blist.empty
      (fun (interpolant, substs) -> 
        Option.list_get (Blist.map (mk_transform interpolant) substs))
      pre_transforms in
    let () = debug (fun _ -> "Done") in
    result

let mk_proc_call_rule_seq 
    ((proc, param_subst), (src_pre, src_cmd, src_post)) 
    ((link_pre, link_cmd, link_post), bridge_rule) = 
  let ((target_pre, _, _) as target_seq) = Proc.get_seq proc in
  let prog_cont = Cmd.get_cont src_cmd in
  assert (Cmd.is_proc_call src_cmd) ;
  assert (let (p, args) = Cmd.dest_proc_call src_cmd in 
    p = (Proc.get_name proc) &&
    (Blist.length args) = (Blist.length (Proc.get_params proc))) ;
  assert (Sl_form.equal src_pre link_pre) ;
  assert (not (Cmd.is_empty prog_cont) || Sl_form.equal src_post link_post) ;
  assert 
    (Cmd.is_empty prog_cont || 
      Cmd.equal (fst (Cmd.split src_cmd)) link_cmd) ; 
  let seq_newparams = Seq.param_subst param_subst target_seq in
  let (link_rl, cont_rl) =
    if Cmd.is_empty prog_cont
      then (Rule.identity, Blist.empty)
      else (Rule.mk_infrule (seq_rule link_post), [Rule.identity]) in
  let or_elim_rl = 
    if Sl_form.is_symheap target_pre
      then Rule.identity
      else Rule.mk_infrule (left_or_elim_rule seq_newparams) in
  let param_rl = 
    if Seq.equal seq_newparams target_seq
      then Rule.identity
      else Rule.mk_infrule (param_subst_rule param_subst target_seq) in
  Rule.compose
    link_rl
    (Rule.compose_pairwise
      bridge_rule
      ((Rule.sequence [
          or_elim_rl ;
          param_rl ;
        ]) :: cont_rl))
      
let mk_symex_proc_call procs =
  fun idx prf ->
    let rl = 
      let ((pre, cmd, post) as src_seq) = Proof.get_seq idx prf in
      try
        let _ = Sl_form.dest pre in
        let (p, args) = Cmd.dest_proc_call cmd in
        let proc = Blist.find 
          (fun x -> 
            (Proc.get_name x) = p 
            && (Blist.length (Proc.get_params x)) = (Blist.length args))
          (procs) in
        let proc_seq = Proc.get_seq proc in
        let param_unifier =
          Sl_term.FList.unify (Proc.get_params proc) args
            Unification.trivial_continuation
            Sl_term.empty_subst in
        let param_sub = Option.get param_unifier in
        let (((pre_cs', pre_hs'), _, _) as inst_proc_seq) =
          Seq.param_subst param_sub proc_seq in
        let proc_call_seq = Seq.with_cmd src_seq (Cmd.mk_proc_call p args) in
        let build_rule_seq = 
          mk_proc_call_rule_seq ((proc, param_sub), src_seq) in
        let mk_rules_from_disj h =
          let proc_sh_pre_seq = Seq.with_pre inst_proc_seq (pre_cs', [h]) in
          let transforms = 
            transform_seq 
              proc_call_seq 
              ~match_post:(Cmd.is_empty (Cmd.get_cont cmd)) 
              proc_sh_pre_seq in
          Blist.map build_rule_seq transforms in
        Rule.choice (Blist.bind mk_rules_from_disj pre_hs')
      with Not_symheap | WrongCmd | Not_found -> Rule.fail in
    rl idx prf

let dobackl idx prf =
  let src_seq = Proof.get_seq idx prf in
  let targets = Rule.all_nodes idx prf in
  let () = debug (fun _ -> "Beginning calculation of potential backlink targets") in
  let transformations =
    Blist.bind
      (fun idx' ->
        Blist.map
          (fun (_, rule) -> (idx', rule))
          (transform_seq src_seq (Proof.get_seq idx' prf)))
      targets in
  let () = debug (fun _ -> "Finished calculation of potential backlink targets") in
  let mk_backlink (targ_idx, rule_sequence) =
    let targ_seq = Proof.get_seq targ_idx prf in
    Rule.compose
      rule_sequence
      (Rule.mk_backrule
        false
        (fun _ _ -> [targ_idx])
        (fun s s' ->
          let tps = 
            if !termination 
              then Seq.tag_pairs targ_seq 
              else Seq.tagpairs_one in
          [tps, "Backl"])) in
  Rule.first (Blist.map mk_backlink transformations) idx prf

(* let generalise_while_rule =                                                                                                                                                                                                                 *)
(*     let rl seq =                                                                                                                                                                                                                            *)
(*       let generalise m h =                                                                                                                                                                                                                  *)
(*         let avoid = ref (Seq.vars seq) in                                                                                                                                                                                                   *)
(*         let gen_term t =                                                                                                                                                                                                                    *)
(*           if Sl_term.Set.mem t m then                                                                                                                                                                                                       *)
(*             (let r = fresh_evar !avoid in avoid := Sl_term.Set.add r !avoid ; r)                                                                                                                                                            *)
(*           else t in                                                                                                                                                                                                                         *)
(*         let gen_pto (x,args) =                                                                                                                                                                                                              *)
(*           let l = Blist.map gen_term (x::args) in (Blist.hd l, Blist.tl l) in                                                                                                                                                               *)
(*             SH.mk                                                                                                                                                                                                                           *)
(*               (Sl_term.Set.fold Sl_uf.remove m h.SH.eqs)                                                                                                                                                                                    *)
(*               (Sl_deqs.filter                                                                                                                                                                                                               *)
(*                 (fun p -> Pair.conj (Pair.map (fun z -> not (Sl_term.Set.mem z m)) p))                                                                                                                                                      *)
(*                 h.SH.deqs)                                                                                                                                                                                                                  *)
(*               (Sl_ptos.endomap gen_pto h.SH.ptos)                                                                                                                                                                                           *)
(*               h.SH.inds in                                                                                                                                                                                                                  *)
(*       try                                                                                                                                                                                                                                   *)
(*         let (pre, cmd, post) = dest_sh_seq seq in                                                                                                                                                                                           *)
(*         let (_, cmd') = Cmd.dest_while cmd in                                                                                                                                                                                               *)
(*         let m = Sl_term.Set.inter (Cmd.modifies cmd') (Sl_heap.vars pre) in                                                                                                                                                                 *)
(*         let subs = Sl_term.Set.subsets m in                                                                                                                                                                                                 *)
(*         Option.list_get (Blist.map                                                                                                                                                                                                          *)
(*           begin fun m' ->                                                                                                                                                                                                                   *)
(*             let pre' = generalise m' pre in                                                                                                                                                                                                 *)
(*             if Sl_heap.equal pre pre' then None else                                                                                                                                                                                        *)
(*             let s' = ([pre'], cmd, post) in                                                                                                                                                                                                 *)
(*             Some ([ (s', tagpairs s', TagPairs.empty) ], "Gen.While")                                                                                                                                                                       *)
(*           end                                                                                                                                                                                                                               *)
(*           subs)                                                                                                                                                                                                                             *)
(*     with Not_symheap | WrongCmd -> [] in                                                                                                                                                                                                    *)
(*   Rule.mk_infrule rl                                                                                                                                                                                                                        *)

let axioms = ref Rule.fail
let rules = ref Rule.fail

let setup (defs, procs) =
  let () = Sl_rules.setup defs in
  let () = Sl_abduce.set_defs defs in
  let symex_proc_unfold = mk_symex_proc_unfold procs in
  let symex_proc_call = mk_symex_proc_call procs in
  rules := 
    Rule.first [ 
      lhs_disj_to_symheaps ;
      simplify ;
      
      Rule.choice [
        
        dobackl ;

        Rule.first [
          symex_skip_rule ;
          symex_assign_rule ;
          symex_load_rule ;
          symex_store_rule ;
          symex_free_rule ;
          symex_new_rule ;
          symex_if_rule ;
          symex_ifelse_rule ;
          symex_while_rule ;
          symex_proc_unfold ;
          symex_proc_call ;
        ] ;
        
        (* generalise_while_rule ; *)
        
        luf defs ;
      ]
    ] ;
  let axioms = 
    Rule.first [
        ex_falso_axiom ; 
        mk_symex_stop_axiom ; 
        mk_symex_empty_axiom
      ] in
  rules := Rule.combine_axioms axioms !rules
