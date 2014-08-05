open Util
open Lib
open Symheap
open Symbols
open MParser
open Parsers

module SH = Sl_heap

let termination = ref false

module Field =
  struct
    type t = string

    let _map = ref Strng.Map.empty
    let _pam = ref Int.Map.empty

    let add f =
      let next_idx = Strng.Map.cardinal !_map in
      _map := Strng.Map.add f next_idx !_map ;
      _pam := Int.Map.add next_idx f !_pam

    let get_index f = Strng.Map.find f !_map

    let get_fields () = Blist.map snd (Int.Map.to_list !_pam)

    let get_no_fields () = Strng.Map.cardinal !_map

    let pp fmt () =
      Format.fprintf fmt "@[%s%s %s%s@]"
        keyw_fields.str symb_colon.str (Strng.FList.to_string (get_fields ())) symb_semicolon.str

    let reset () =
      _map := Strng.Map.empty ;
      _pam := Int.Map.empty

    let to_melt f = Latex.texttt (Latex.text f)
    
    let parse st = parse_ident st
  end
  
exception WrongCmd

module Cond =
  struct
    type t =
      | Eq of Sl_term.t * Sl_term.t
      | Deq of Sl_term.t * Sl_term.t
      | Non_det

    let mk_eq e1 e2 = Eq(e1,e2)
    let mk_deq e1 e2 = Deq(e1,e2)
    let mk_non_det () = Non_det

    let is_deq = function
      | Deq(_, _) -> true
      | Eq _ | Non_det -> false
    let is_eq = function
      | Eq(_, _) -> true
      | Deq _ | Non_det -> false
    let is_non_det = function
      | Non_det -> true
      | Eq _ | Deq _ -> false
    let is_det c = not (is_non_det c)

    let dest = function
      | Eq(e1, e2) | Deq(e1, e2) -> (e1,e2)
      | Non_det -> raise WrongCmd

    let terms = function
      | Non_det -> Sl_term.Set.empty
      | Deq(x,y) | Eq(x,y) -> Sl_term.Set.add x (Sl_term.Set.singleton y)

    let vars cond = Sl_term.filter_vars (terms cond)

    let equal cond cond' = match (cond, cond') with
      | (Non_det, Non_det) -> true
      | (Eq(x,y), Eq(x',y')) | (Deq(x,y), Deq(x',y')) ->
        Sl_term.equal x x' && Sl_term.equal y y'
      | _ -> false

    let pp fmt = function
      | Non_det ->
        Format.fprintf fmt "@[%s@]" symb_star.str
      | Eq(x,y) ->
        Format.fprintf fmt "@[%a%s%a@]" Sl_term.pp x symb_eq.str Sl_term.pp y
      | Deq(x,y) ->
        Format.fprintf fmt "@[%a%s%a@]" Sl_term.pp x symb_deq.str Sl_term.pp y

    let to_melt = function
      | Non_det -> symb_star.melt
      | Eq(x,y) -> Latex.concat [Sl_term.to_melt x; symb_eq.melt; Sl_term.to_melt y]
      | Deq(x,y) -> Latex.concat [Sl_term.to_melt x; symb_deq.melt; Sl_term.to_melt y]

    let fork f c =
      if is_non_det c then (f,f) else
      let pair = dest c in
      let f' =  { f with SH.eqs=UF.add pair f.SH.eqs } in
      let f'' = { f with SH.deqs=Deqs.add pair f.SH.deqs } in
      let (f',f'') = if is_deq c then (f'',f') else (f',f'') in
      (f',f'')
    
    let parse st =
      ( attempt (parse_symb symb_star >>$ mk_non_det ()) <|>
        attempt (UF.parse |>> Fun.uncurry mk_eq) <|>
                (Deqs.parse |>> Fun.uncurry mk_deq) <?> "Cond") st
  end


module Cmd =
  struct
    type cmd_t =
      | Stop
      | Skip
      | Assign of Sl_term.t * Sl_term.t
      | Load of Sl_term.t * Sl_term.t * Field.t
      | Store of Sl_term.t * Field.t * Sl_term.t
      | New of Sl_term.t
      | Free of Sl_term.t
      | If of Cond.t * t
      | IfElse of Cond.t * t * t
      | While of Cond.t * t
    and basic_t = { label:int option; cmd:cmd_t }
    and t = basic_t list

    let get_cmd c = if c=[] then raise WrongCmd else (Blist.hd c).cmd
    let get_cont c = if c=[] then raise WrongCmd else Blist.tl c

    let is_empty c = c=[]
    let is_not_empty c = not (is_empty c)

    let is_assign c = is_not_empty c && match get_cmd c with
      | Assign _ -> true
      | _ -> false
    let is_load c = is_not_empty c && match get_cmd c with
      | Load _ -> true
      | _ -> false
    let is_store c = is_not_empty c && match get_cmd c with
      | Store _ -> true
      | _ -> false
    let is_new c = is_not_empty c && match get_cmd c with
      | New _ -> true
      | _ -> false
    let is_free c = is_not_empty c && match get_cmd c with
      | Free _ -> true
      | _ -> false
    let is_stop c = is_not_empty c && match get_cmd c with
      | Stop -> true
      | _ -> false
    let is_skip c = is_not_empty c && match get_cmd c with
      | Skip -> true
      | _ -> false

    let is_basic c = is_not_empty c && match get_cmd c with
      | Assign _ | Load _ | Store _ | New _ | Free _ | Stop | Skip -> true
      | _ -> false

    let is_if c = is_not_empty c && match get_cmd c with
      | If _ -> true
      | _ -> false
    let is_ifelse c = is_not_empty c && match get_cmd c with
      | IfElse _ -> true
      | _ -> false
    let is_while c = is_not_empty c && match get_cmd c with
      | While _ -> true
      | _ -> false

    let mklc c = { label=None; cmd=c }
    let mk_basic c = [ { label=None; cmd=c } ]
    let mk_assign x e = mk_basic (Assign(x,e))
    let mk_load x e s =  mk_basic (Load(x,e,s))
    let mk_store e1 s e2 = mk_basic (Store(e1,s,e2))
    let mk_new x = mk_basic (New(x))
    let mk_free e = mk_basic (Free(e))
    let mk_stop = mk_basic (Stop)
    let mk_skip = mk_basic (Skip)
    let mk_if cond cmd = mk_basic (If(cond, cmd))
    let mk_ifelse cond cmd cmd' = mk_basic (IfElse(cond, cmd, cmd'))
    let mk_while cond cmd = mk_basic (While(cond, cmd))
    let mk_seq cmd cmd' = cmd @ cmd'
    let mk_from_list l = Blist.flatten l

    (* TODO: Finish improving parsing of commands to give better error feedback for syntax errors *)
    let rec parse_atomic_cmd st =
      (   try_prefix (parse_symb keyw_stop) (fun p -> p >>$ Stop)
      <|> try_prefix (parse_symb keyw_skip) (fun p -> p >>$ Skip)
      <|> try_prefix (parse_symb keyw_free) (fun p -> 
            p >> Tokens.parens Sl_term.parse |>> (fun v ->
            assert (Sl_term.is_var v) ; Free v))
      <|> try_prefix (Sl_term.parse << (parse_symb symb_fld_sel))
            (fun p -> p >>= (fun v ->
            parse_ident >>= (fun id ->
            parse_symb symb_assign >>
            Sl_term.parse |>> (fun t ->
            assert (Sl_term.is_var v) ; Store(v,id,t)))))
(*
      <|> try_prefix (Sl_term.parse << (parse_symb symb_assign))
            (fun p -> p >>= (fun v ->
              
            (parse_symb keyw_new) >>
            Tokens.parens (skip_string "")))
            (fun p -> p |>> (fun v -> assert (Sl_term.is_var v) ; New v))
*)
       << parse_symb symb_semicolon ) st 
    and parse_block_cmd st =
      ( message "Block commands not implemented yet" ) st
    and parse_cmd st =
      let parse_cmdlist_endedby symb st = 
        ( expect_before parse (parse_symb symb) "Expecting CmdList" ) st in
      (* (   parse_atomic_cmd               *)
      (* <|> parse_block_cmd <?> "Cmd" ) st *)
      (   attempt (parse_symb keyw_stop >> parse_symb symb_semicolon >>$ Stop)
      <|> attempt (parse_symb keyw_skip >> parse_symb symb_semicolon >>$ Skip)
      <|> attempt (parse_symb keyw_free >>
          Tokens.parens Sl_term.parse >>= (fun v ->
          parse_symb symb_semicolon >>$ (assert (Sl_term.is_var v) ; Free v)))
  (* | IF; cond = condition; THEN; cmd1 = command; ELSE; cmd2 = command; FI { P.Cmd.mk_ifelse cond cmd1 cmd2 } *)
  (* | IF; cond = condition; LB; cmd1 = command; RB; ELSE; LB; cmd2 = command; RB { P.Cmd.mk_ifelse cond cmd1 cmd2 } *)
      <|> attempt (parse_symb keyw_if >>
          Cond.parse >>= (fun cond ->
              (parse_symb keyw_then >>
              (parse_cmdlist_endedby keyw_else) >>= (fun cmd1 ->
              parse_symb keyw_else >>
              (parse_cmdlist_endedby keyw_fi) >>= (fun cmd2 ->
              parse_symb keyw_fi >>$ (IfElse(cond,cmd1,cmd2)))))
				  <|> ((Tokens.braces parse) >>= (fun cmd1 ->
							parse_symb keyw_else >>
              Tokens.braces (parse_cmdlist_endedby symb_rb) |>> (fun cmd2 ->
              IfElse(cond,cmd1,cmd2))))
					))
  (* | IF; cond = condition; THEN; cmd = command; FI { P.Cmd.mk_if cond cmd }                                  *)
  (* | IF; cond = condition; LB; cmd = command; RB { P.Cmd.mk_if cond cmd }                                  *)
      <|> attempt (parse_symb keyw_if >>
          Cond.parse >>= (fun cond ->
              (parse_symb keyw_then >>
              (parse_cmdlist_endedby keyw_fi) >>= (fun cmd ->
              parse_symb keyw_fi >>$ (If(cond,cmd))))
					<|> (Tokens.braces (parse_cmdlist_endedby symb_rb) |>> (fun cmd ->
             If(cond,cmd)))
					))
  (* | WHILE; cond = condition; DO; cmd = command; OD { P.Cmd.mk_while cond cmd }                              *)
  (* | WHILE; cond = condition; LB; cmd = command; RB { P.Cmd.mk_while cond cmd }                              *)
      <|> attempt (parse_symb keyw_while >>
          Cond.parse >>= (fun cond ->
              (parse_symb keyw_do >>
              (parse_cmdlist_endedby keyw_od) >>= (fun cmd ->
              parse_symb keyw_od >>$ (While(cond,cmd))))
					<|> (Tokens.braces (parse_cmdlist_endedby symb_rb) |>> (fun cmd ->
              While(cond,cmd)))
					))
  (*   | v = var; FLD_SEL; fld = IDENT; ASSIGN; t = term                                                       *)
      <|> attempt (Sl_term.parse >>= (fun v ->
          parse_symb symb_fld_sel >>
          parse_ident >>= (fun id ->
          parse_symb symb_assign >>
          Sl_term.parse >>= (fun t ->
          parse_symb symb_semicolon >>$ (assert (Sl_term.is_var v) ; Store(v,id,t))))))
  (*   v = var; ASSIGN; NEW; LP; RP { P.Cmd.mk_new v }                            *)
      <|> attempt (Sl_term.parse <<
          parse_symb symb_assign <<
          parse_symb keyw_new <<
          parse_symb symb_lp <<
          parse_symb symb_rp <<
          parse_symb symb_semicolon |>> (fun v ->
          assert (Sl_term.is_var v) ; New v))
  (*   | v1 = var; ASSIGN; v2 = var; FLD_SEL; fld = IDENT                                                      *)
      <|> attempt (Sl_term.parse >>= (fun v1 ->
          parse_symb symb_assign >>
          Sl_term.parse >>= (fun v2 ->
          parse_symb symb_fld_sel >>
          parse_ident >>= (fun id ->
          parse_symb symb_semicolon >>$ (
          assert (Sl_term.is_var v1 && Sl_term.is_var v2) ; Load(v1,v2,id))))))
    (* | v = var; ASSIGN; t = term { P.Cmd.mk_assign v t } *)
      <|> attempt (Sl_term.parse >>= (fun v -> 
          parse_symb symb_assign >> 
          Sl_term.parse >>= (fun t -> 
          parse_symb symb_semicolon >>$ (assert (Sl_term.is_var v) ; Assign(v,t)))))
      <?> "Cmd") st
    and parse st = 
      ( many1 parse_cmd |>> Blist.map mklc) st

    let _dest_stop = function
      | Stop -> ()
      | _ -> raise WrongCmd
    let _dest_skip = function
      | Skip -> ()
      | _ -> raise WrongCmd
    let _dest_assign = function
      | Assign(x,e) -> (x,e)
      | _ -> raise WrongCmd
    let _dest_load = function
      | Load(x,e,s) -> (x,e,s)
      | _ -> raise WrongCmd
    let _dest_store = function
      | Store(e1,s,e2) -> (e1,s,e2)
      | _ -> raise WrongCmd
    let _dest_new = function
      | New(x) -> x
      | _ -> raise WrongCmd
    let _dest_free = function
      | Free(e) -> e
      | _ -> raise WrongCmd
    let _dest_if = function
      | If(cond,cmd) -> (cond,cmd)
      | _ -> raise WrongCmd
    let _dest_ifelse = function
      | IfElse(cond,cmd,cmd') -> (cond,cmd,cmd')
      | _ -> raise WrongCmd
    let _dest_while = function
      | While(cond,cmd) -> (cond,cmd)
      | _ -> raise WrongCmd
    let _dest_deref = function
      | Load(x,e,s) -> e
      | Store(e1,s,e2) -> e1
      | Free(e) -> e
      | _ -> raise WrongCmd

    let dest_cmd f = fun c -> f (get_cmd c)

    let dest_stop = dest_cmd _dest_stop
    let dest_skip = dest_cmd _dest_skip
    let dest_assign = dest_cmd _dest_assign
    let dest_load = dest_cmd _dest_load
    let dest_store = dest_cmd _dest_store
    let dest_new = dest_cmd _dest_new
    let dest_free = dest_cmd _dest_free
    let dest_deref = dest_cmd _dest_deref
    let dest_if = dest_cmd _dest_if
    let dest_ifelse = dest_cmd _dest_ifelse
    let dest_while = dest_cmd _dest_while
    let dest_empty c = if c=[] then () else raise WrongCmd

    let number c =
      let rec aux n = function
        | [] -> ([], n)
        | c::l ->
          begin match c.cmd with
            | Assign _ | Load _ | Store _ | New _ | Free _ | Stop | Skip ->
              let c' = { label=Some n; cmd=c.cmd } in
              let (l', n') = aux (n+1) l in
              (c'::l', n')
            | If(cond, subc) ->
              let (subc', n') = aux (n+1) subc in
              let c' = { label=Some n; cmd=If(cond, subc') } in
              let (l', n'') = aux n' l in
              (c'::l', n'')
            | IfElse(cond, subc1,subc2) ->
              let (subc1', n') = aux (n+1) subc1 in
              let (subc2', n'') = aux (n'+1) subc2 in
              let c' = { label=Some n; cmd=IfElse(cond, subc1',subc2') } in
              let (l', n'') = aux n'' l in
              (c'::l', n'')
            | While(cond, subc) ->
              let (subc', n') = aux (n+1) subc in
              let c' = { label=Some n; cmd=While(cond, subc') } in
              let (l', n'') = aux n' l in
              (c'::l', n'')
          end in
      fst (aux 0 c)


    let rec cmd_terms = function
      | Stop | Skip -> Sl_term.Set.empty
      | New(x) | Free(x) -> Sl_term.Set.singleton x
      | Assign(x,e) | Load(x,e,_) | Store(x,_,e) -> Sl_term.Set.of_list [x; e]
      | If(cond,cmd) -> Sl_term.Set.union (Cond.vars cond) (terms cmd)
      | IfElse(cond,cmd,cmd') ->
        Sl_term.Set.union (Sl_term.Set.union (Cond.vars cond) (terms cmd)) (terms cmd')
      | While(cond,cmd) -> Sl_term.Set.union (Cond.vars cond) (terms cmd)
    and terms l =
      Blist.fold_left (fun s c -> Sl_term.Set.union s (cmd_terms c.cmd)) Sl_term.Set.empty l

    let vars cmd = Sl_term.filter_vars (terms cmd)

    let rec cmd_modifies = function
      | Stop | Skip | Free _ -> Sl_term.Set.empty
      | New(x) | Assign(x,_) | Load(x,_,_) | Store(x,_,_) -> Sl_term.Set.singleton x
      | If(_,cmd) | While(_,cmd) -> modifies cmd
      | IfElse(_,cmd,cmd') -> Sl_term.Set.union (modifies cmd) (modifies cmd')
    and modifies l =
      Blist.fold_left 
        (fun s c -> Sl_term.Set.union s (cmd_modifies c.cmd)) Sl_term.Set.empty l

    let rec cmd_equal cmd cmd' = match (cmd, cmd') with
      | (Stop, Stop) | (Skip, Skip) -> true
      | (New(x), New(y)) | (Free(x), Free(y)) -> Sl_term.equal x y
      | (Assign(x,e), Assign(x',e')) -> Sl_term.equal x x' && Sl_term.equal e e'
      | (Load(x,e,f), Load(x',e',f')) | (Store(x,f,e), Store(x',f',e')) ->
        Sl_term.equal x x' && Sl_term.equal e e' && f=f'
      | (While(cond,cmd), While(cond',cmd')) | (If(cond,cmd), If(cond',cmd')) ->
        Cond.equal cond cond' && equal cmd cmd'
      | (IfElse(cond,cmd1,cmd2), IfElse(cond',cmd1',cmd2')) ->
        Cond.equal cond cond' && equal cmd1 cmd1' && equal cmd2 cmd2'
      | _ -> false
    and equal l l' = match (l,l') with
      | ([], []) -> true
      | ([], _) | (_, []) -> false
      | (c::tl, c'::tl') -> cmd_equal c.cmd c'.cmd && equal tl tl'

    let number_width = ref 3
    let indent_by = ref 2

    let pp_label ?(abbr=false) indent fmt c =
      let label = match (c.label, abbr) with
        | (None, false) -> String.make (!number_width+2) ' '
        | (None, true) -> ""
        | (Some n, false) -> Printf.sprintf "%*d: " !number_width n
        | (Some n, true) -> Printf.sprintf "%d: " n in
      let extra_indent = if abbr then "" else String.make indent ' ' in
      Format.pp_print_string fmt (label ^ extra_indent)

    let rec pp_cmd ?(abbr=false) indent fmt c = match c.cmd with
      | Stop -> Format.fprintf fmt "%s" keyw_stop.str
      | Skip -> Format.fprintf fmt "%s" keyw_skip.str
      | New(x) ->
        Format.fprintf fmt "%a%s%s%s%s"
          Sl_term.pp x symb_assign.sep keyw_new.str symb_lp.str symb_rp.str
      | Free(x) ->
        Format.fprintf fmt "%s%s%a%s"
          keyw_free.str symb_lp.str Sl_term.pp x symb_rp.str
      | Assign(x,e) ->
        Format.fprintf fmt "%a%s%a"
          Sl_term.pp x symb_assign.sep Sl_term.pp e
      | Load(x,e,f) ->
        Format.fprintf fmt "%a%s%a%s%s"
          Sl_term.pp x symb_assign.sep Sl_term.pp e symb_fld_sel.str f
      | Store(x,f,e) ->
        Format.fprintf fmt "%a%s%s%s%a"
          Sl_term.pp x symb_fld_sel.str f symb_assign.sep Sl_term.pp e
      | If(cond,cmd) ->
        if abbr then
          Format.fprintf fmt "%s %a %s %a... %s"
            keyw_if.str Cond.pp cond keyw_then.str (pp_label ~abbr 0) (Blist.hd cmd) keyw_fi.str
        else
          Format.fprintf fmt "%s %a %s@\n%a@\n%s"
            keyw_if.str Cond.pp cond keyw_then.str (pp ~abbr (indent+ !indent_by)) cmd
              ((String.make (!number_width+indent+2) ' ') ^ keyw_fi.str)
      | IfElse(cond,cmd,cmd') ->
        if abbr then
          Format.fprintf fmt "%s %a %s %a... %s %a... %s"
            keyw_if.str Cond.pp cond keyw_then.str (pp_label ~abbr 0) (Blist.hd cmd)
            keyw_else.str (pp_label ~abbr 0) (Blist.hd cmd') keyw_fi.str
        else
          Format.fprintf fmt "%s %a %s@\n%a@\n%s@\n%a@\n%s"
            keyw_if.str Cond.pp cond keyw_then.str (pp ~abbr (indent+ !indent_by)) cmd
            keyw_else.str (pp ~abbr (indent+ !indent_by)) cmd'
              ((String.make (!number_width+indent+2) ' ') ^ keyw_fi.str)
      | While(cond,cmd) ->
        if abbr then
          Format.fprintf fmt "%s %a %s %a... %s"
            keyw_while.str Cond.pp cond keyw_do.str
            (pp_label ~abbr 0) (Blist.hd cmd) keyw_od.str
        else
          Format.fprintf fmt "%s %a %s@\n%a@\n%s"
            keyw_while.str Cond.pp cond keyw_do.str
            (pp ~abbr (indent+ !indent_by)) cmd
            ((String.make (!number_width+indent+2) ' ') ^ keyw_od.str)
    and pp_lcmd ?(abbr=false) indent fmt c =
      Format.fprintf fmt "%a%a"
        (pp_label ~abbr indent) c (pp_cmd ~abbr indent) c
    and pp ?(abbr=false) indent fmt = function
      | [] -> ()
      | [ c ] -> pp_lcmd ~abbr indent fmt c
      | hd::tl ->
        if abbr then
          Format.fprintf fmt "%a%s %a..."
            (pp_lcmd ~abbr indent) hd symb_semicolon.str
            (pp_label ~abbr indent) (Blist.hd tl)
        else
          Format.fprintf fmt "%a%s@\n%a"
            (pp_lcmd ~abbr indent) hd symb_semicolon.str (pp ~abbr indent) tl

    let to_string cmd = mk_to_string (pp ~abbr:true 0) cmd
     
    let to_melt_label c = match c.label with
        | None -> Latex.empty
        | Some n -> Latex.text ((string_of_int n) ^ " : ")

    let rec to_melt_cmd c = match c.cmd with
      | Stop -> keyw_stop.melt
      | Skip -> keyw_skip.melt
      | New(x) ->
        Latex.concat
          [ Sl_term.to_melt x; symb_assign.melt;
            keyw_new.melt; symb_lp.melt; symb_rp.melt; ]
      | Free(x) ->
        Latex.concat
          [ keyw_free.melt; symb_lp.melt; Sl_term.to_melt x; symb_rp.melt ]
      | Assign(x,e) ->
        Latex.concat
          [ Sl_term.to_melt x; symb_assign.melt; Sl_term.to_melt e ]
      | Load(x,e,f) ->
        Latex.concat
          [ Sl_term.to_melt x; symb_assign.melt; Sl_term.to_melt e;
            symb_fld_sel.melt; Field.to_melt f ]
      | Store(x,f,e) ->
        Latex.concat
          [ Sl_term.to_melt x; symb_fld_sel.melt;
            Field.to_melt f; symb_assign.melt; Sl_term.to_melt e ]
      | If(cond,cmd) ->
        Latex.concat
          [ keyw_if.melt; ltx_math_space; Cond.to_melt cond; ltx_math_space;
            keyw_then.melt; ltx_math_space; to_melt_label (Blist.hd cmd);
            Latex.ldots; keyw_fi.melt ]
      | IfElse(cond,cmd,cmd') ->
        Latex.concat
          [ keyw_if.melt; ltx_math_space; Cond.to_melt cond; ltx_math_space;
            keyw_then.melt; ltx_math_space; to_melt_label (Blist.hd cmd);
            Latex.ldots; keyw_else.melt; to_melt_label (Blist.hd cmd');
            Latex.ldots; keyw_fi.melt ]
      | While(cond,cmd) ->
        Latex.concat
          [ keyw_while.melt; ltx_math_space; Cond.to_melt cond; ltx_math_space;
            keyw_do.melt; ltx_math_space; to_melt_label (Blist.hd cmd);
            Latex.ldots; keyw_od.melt ]
    and to_melt_lcmd c = Latex.concat [to_melt_label c; to_melt_cmd c]
    and to_melt = function
      | [] -> Latex.epsilon
      | [ c ] -> to_melt_lcmd c
      | hd::tl ->
        Latex.concat
          [ to_melt_lcmd hd; symb_semicolon.melt;
          to_melt_label (Blist.hd tl); Latex.ldots ]

  end

module Proc =
  struct
    
    let add p = ()
    
    (* precondition: PRECONDITION; COLON; f = formula; SEMICOLON { f } *)
    let parse_precondition st = 
      ( parse_symb keyw_precondition >>
        parse_symb symb_colon >>
        Sl_form.parse >>= (fun f ->
        parse_symb symb_semicolon >>$ f) <?> "Precondition") st

    (* postcondition: POSTCONDITION; COLON; f = formula; SEMICOLON { f } *)
    let parse_postcondition st = 
      ( parse_symb keyw_postcondition >>
        parse_symb symb_colon >>
        Sl_form.parse >>= (fun f ->
        parse_symb symb_semicolon >>$ f) <?> "Postcondition") st

    let parse_named st = 
      let parse_params st =
      let rec parse_params' acc st =
      let tail st =
      let try_parse_next_param check msg st = 
        (   look_ahead(Sl_term.parse >>= (fun p -> 
              if (check p) then zero else return ()))
        <|> fail msg) st in
      ((followed_by Sl_term.parse "") >>
      (try_parse_next_param (fun p -> Sl_term.is_nil p) "Not a formal parameter") >>
      (try_parse_next_param (fun p -> Sl_term.is_exist_var p) 
        "Not a formal parameter - must not be primed (')") >>
      (try_parse_next_param (fun p -> List.mem p acc) "Duplicate parameter") >>
      Sl_term.parse >>= (fun p -> parse_params' (p::acc))) st in
      (   (if (List.length acc == 0) then tail else ((parse_symb symb_comma) >> tail)) 
      <|> (return acc) ) st in
      parse_params' [] st in
      (parse_symb keyw_proc >> 
      parse_ident >>= (fun id ->
      (Tokens.parens parse_params) >>= (fun params ->
      parse_precondition >>= (fun pre ->
      parse_postcondition >>= (fun post ->
      Tokens.braces 
        (expect_before Cmd.parse (parse_symb symb_rb) "Expecting CmdList") |>> 
      (fun body ->
        return (id, params, pre, post, body) <?> "Procedure" )))))) st
    
    let parse_unnamed st = 
      (parse_precondition >>= (fun pre ->
      parse_postcondition >>= (fun post ->
      Cmd.parse >>= 
      (fun body ->
        return (pre, body, post)))) <?> "CmdList") st
    
  end

let program_pp fmt cmd =
  Format.fprintf fmt "%a@\n%a" Field.pp () (Cmd.pp 0) cmd

let pp_cmd fmt cmd =
  Cmd.pp ~abbr:true 0 fmt cmd

module Seq =
  struct
    type t = Sl_form.t * Cmd.t * Sl_form.t

    let tagset_one = Tags.singleton 1
		let tagpairs_one = TagPairs.mk tagset_one
    let tags (pre,cmd,_) = if !termination then Sl_form.tags pre else tagset_one

		(* Do we want the vars from the postcondition as well, or not? *)
		(* 		let vars (pre,_,post) = Sl_term.Set.union (Sl_form.vars pre) (Sl_form.vars post) *)
		let vars (pre,_,_) = Sl_form.vars pre
		
		(* Do we want the vars from the postcondition as well, or not? *)
		(*     let terms (pre,_,post) = Sl_term.Set.union (Sl_form.terms pre) (Sl_form.terms post) *)
		let terms (pre,_,_) = Sl_form.terms pre

		let subst (theta,theta') (pre,cmd,post) = 
			(Sl_form.subst theta pre, cmd, Sl_form.subst theta' post)
    
		let to_string (pre,cmd,post) =
      symb_turnstile.sep ^ 
			symb_lb.str ^ (Sl_form.to_string pre) ^ symb_rb.str ^ " " ^ 
			(Cmd.to_string cmd) ^
			symb_lb.str ^ (Sl_form.to_string post) ^ symb_rb.str
    
		let to_melt (pre,cmd,post) =
      ltx_mk_math
        (Latex.concat [ symb_turnstile.melt; 
				 								symb_lb.melt; Sl_form.to_melt pre; symb_rb.melt;
												Cmd.to_melt cmd;
												symb_lb.melt; Sl_form.to_melt post; symb_rb.melt ])

    let is_subsumed (pre,cmd,post) (pre',cmd',post') =
      Cmd.equal cmd cmd' &&
      (* pre |- pre' *)
      Sl_form.subsumed_wrt_tags Tags.empty pre' pre &&
      (* post' |- post *)
      Sl_form.subsumed_wrt_tags Tags.empty post post'
    
    let subsumed_wrt_tags tags (pre,cmd,post) (pre',cmd',post') =
      Cmd.equal cmd cmd' && 
      Sl_form.subsumed_wrt_tags tags pre' pre &&
      Sl_form.subsumed_wrt_tags tags post post'
		
    let uni_subsumption ((pre,cmd,post) as s) ((pre',cmd',post') as s') =
      if not (Cmd.equal cmd cmd') then None else
      let tags = Tags.inter (tags s) (tags s') in
      let valid_pre theta =
        if Sl_term.Map.exists
          (fun k v -> Sl_term.is_univ_var k && not (Sl_form.equates pre k v)) theta
          then None
        else 
  				if not !termination then Some theta else 
          let s'' = subst (theta, Sl_term.empty_subst) s' in
          let tags' = Tags.fold
            ( fun t acc ->
              let new_acc = Tags.add t acc in
              if subsumed_wrt_tags new_acc s s'' then new_acc else acc
            ) tags Tags.empty in
          if not (Tags.is_empty tags') then Some theta else None
        in
      let valid_post theta =
        if Sl_term.Map.exists
          (fun k v -> Sl_term.is_univ_var k && not (Sl_form.equates post k v)) theta
          then None
        else Some theta
        in
      let theta  = Sl_form.right_subsumption valid_pre Sl_term.empty_subst pre' pre in
      let theta' = Sl_form.right_subsumption valid_post Sl_term.empty_subst post post' in
      match (theta, theta') with
        | (None, _) -> None
        | (_, None) -> None
        | (Some theta, Some theta') -> Some (theta, theta')

    let pp fmt (pre,cmd,post) =
      Format.fprintf fmt "@[%s{%a}%a{%a}@]"
        symb_turnstile.sep
				Sl_form.pp pre 
				(Cmd.pp ~abbr:true 0) cmd
				Sl_form.pp post

    let equal (pre, cmd, post) (pre', cmd', post') = 
			Cmd.equal cmd cmd' && 
      Sl_form.equal pre pre' && 
      Sl_form.equal post post'
      
  end

let program_vars = ref Sl_term.Set.empty

let set_program p =
  program_vars := Cmd.vars p

let vars_of_program () = !program_vars

(* remember prog vars when introducing fresh ones *)
let fresh_uvar s = Sl_term.fresh_uvar (Sl_term.Set.union !program_vars s)
let fresh_uvars s i = Sl_term.fresh_uvars (Sl_term.Set.union !program_vars s) i
let fresh_evar s = Sl_term.fresh_evar (Sl_term.Set.union !program_vars s)
let fresh_evars s i = Sl_term.fresh_evars (Sl_term.Set.union !program_vars s) i

(* again, treat prog vars as special *)
let freshen_case_by_seq seq case =
  Sl_indrule.freshen (Sl_term.Set.union !program_vars (Seq.vars seq)) case

(* fields: FIELDS; COLON; ils = separated_nonempty_list(COMMA, IDENT); SEMICOLON  *)
(*     { List.iter P.Field.add ils }                                              *)
let parse_fields st = 
  ( parse_symb keyw_fields >>
    parse_symb symb_colon >>
    sep_by1 Field.parse (parse_symb symb_comma) >>= (fun ils ->
    parse_symb symb_semicolon >>$ List.iter Field.add ils) <?> "Fields") st

(* procedures *)
let parse_procs st = 
  ( many Proc.parse_named >>= (fun procs -> return (List.iter Proc.add procs)) ) st
  
let parse_main st =
  ( Proc.parse_unnamed << eof) st

(* fields; procs; p = precondition; q = postcondition; cmd = command; EOF { (p, cmd, q) } *)
let parse st = 
  ( parse_fields >>
    parse_procs >>
    (parse_main <?> "Main procedure") <?> "Program") st

let of_channel c =
  handle_reply (parse_channel parse c ())