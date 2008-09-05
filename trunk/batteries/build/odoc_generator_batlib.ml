(*
 * Odoc_generator_batlib - custom documentation generator for Batteries
 * Copyright (C) 2008 Maxence Guesdon
 * Copyright (C) 2008 David Teller, LIFO, Universite d'Orleans
 * 
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version,
 * with the special exception on linking described in file LICENSE.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *)
open Odoc_info;;
open Module;;
open List;;
open Odoc_info
module Naming = Odoc_html.Naming
open Odoc_info.Value
open Odoc_info.Module
open Odoc_info.Type
open Odoc_info.Class
open Odoc_info.Exception

let concat a b =
  if String.length b = 0 then a
  else Name.concat a b

let primitive_types_names =
  ["string", "Batlib.Data.Text.String.t";
   "array",  "Batlib.Data.Containers.Mutable.Array.t" ;
   "lazy_t", "Batlib.Data.Containers.Persistent.Lazy.t";
   "list",   "Batlib.Data.Containers.Persistent.List.t";
   "int32",  "Batlib.Data.Numeric.Int32.t";
   "int64",  "Batlib.Data.Numeric.Int64.t";
   "nativeint", "Batlib.Data.Numeric.Nativeint.t"]

(*let primitive_types_names =
  ["string",    "String.t";
   "array",     "Array.t" ;
   "lazy_t",    "Lazy.t";
   "list",      "List.t";
   "int32",     "Int32.t";
   "int64",     "Int64.t";
   "nativeint", "Nativeint.t"]*)

(*In the future, add int, char, bool, unit, float, exn,
  option, format4*)

let end_of_name name =
  Name.get_relative (Name.father (Name.father name)) name

(*let default_info =
{
    i_desc = None;
    i_authors = [];
    i_version = None;
    i_sees = [];
    i_since = None;
    i_deprecated = None;
    i_params = [];
    i_raised_exceptions = [];
    i_return_value = None;
    i_custom = []
}

let add_to_info c = function
  | None   -> Some {(default_info) with i_custom = [c]};
  | Some i -> Some {(i) with i_custom = c::i.i_custom}

let add_rename result =
  add_to_info ("rename", [Ref (result, Some RK_module)])*)

let get_replacing = function
  | None   -> 
      None
  | Some i -> 
      try match List.assoc "replace" i.i_custom with
	| []      -> 
	    None
	| [Raw s] -> 
	    Some s
	| h::_ as x-> warning ("Weird replacement "^(string_of_text x)); Some (string_of_text x)
      with Not_found -> 
	None

(**
   [rebuild_structure m] walks through list [m] and rebuilds it as a forest
   of modules and sub-modules.

   - Resolving aliases: if we have a module [A] containing [module B = C], module [C]
   is renamed [A.B] and we keep that renaming for reference generation.
   - Resolving inclusions: if we have a module [A] containing [include C], the contents
   of module [C] are copied into [A] and we fabricate a renaming from [C] to [A] for
   reference generation.

   @return [(m, r)], where [m] is the new list of modules and [r] is a mapping from
   old module names to new module names.
*)
let rebuild_structure modules =
  let all_renamed_modules      = Hashtbl.create 100
  and all_renamed_module_types = Hashtbl.create 100  in
  let add_renamed_module old current =
    warning ("Setting module renaming from "^old^" to "^current);
    try 
      let further_references = Hashtbl.find all_renamed_modules current in
	warning ("... actually setting renaming from "^old^" to "^further_references);
	Hashtbl.add all_renamed_modules old further_references
    with Not_found -> Hashtbl.add all_renamed_modules old current
  and add_renamed_module_type old current =
    warning ("Setting module type renaming from "^old^" to "^current);
    try 
      let further_references = Hashtbl.find all_renamed_module_types current in
	warning ("... actually setting renaming from "^old^" to "^further_references);
	Hashtbl.add all_renamed_module_types old further_references
    with Not_found -> Hashtbl.add all_renamed_module_types old current
  in
(*First pass: build hierarchy*)
  let rec handle_kind path (m:t_module) = function
    | Module_struct     x      -> Module_struct (List.flatten (List.map (handle_module_element path m) x))
    | Module_alias      x      -> Module_alias (handle_alias path m x)
    | Module_functor    (p, k) -> Module_functor (p, handle_kind path m k)
    | Module_apply      (x, y) -> Module_apply (handle_kind path m x, handle_kind path m y)
    | Module_with       (k, s) -> Module_with (handle_type_kind path m k,  s)
    | Module_constraint (x, y) -> Module_constraint (handle_kind path m x, handle_type_kind path m y)
  and handle_module_element path m = function
    | Element_module    x      -> [Element_module      (handle_module path m x)]
    | Element_module_type x    -> [Element_module_type (handle_module_type path m x)]
    | Element_module_comment _  as y  -> [y]
    | Element_class x                ->
	[Element_class     {(x) with cl_name  = concat path (Name.simple x.cl_name)}]
    | Element_class_type x           ->
	[Element_class_type{(x) with clt_name = concat path (Name.simple x.clt_name)}]
    | Element_value x                ->
	[Element_value     {(x) with val_name = concat path (Name.simple x.val_name)}]
    | Element_exception x            ->
	[Element_exception {(x) with ex_name  = concat path (Name.simple x.ex_name)}]
    | Element_type x                 ->
	[Element_type {(x) with ty_name = concat path (Name.simple x.ty_name)}]
    | Element_included_module x as y ->
(*	warning ("Meeting inclusion "^x.im_name);*)
	match x.im_module with
	  | Some (Mod a) -> 
	      warning ("This is an included module, we'll treat it as "^path);
	      let a' = handle_module path m {(a) with m_name = ""} in
		(
		  match a'.m_kind with
		    | Module_struct l -> 
			(*Copy the contents of [a] into [m]*)
			(*Copy the information on [a] into [m]*)
(*			warning ("Structure of the module is simple");*)
			m.m_info <- Odoc_merge.merge_info_opt Odoc_types.all_merge_options m.m_info a'.m_info;
			add_renamed_module a.m_name m.m_name;
			add_renamed_module (Name.get_relative m.m_name a.m_name) m.m_name;
			l 
		    | _               -> 
(*			warning ("Structure of the module is complex");*)
			[Element_included_module {(x) with im_module = Some (Mod a')}]
			  (*Otherwise, it's too complicated*)
		)
	  | Some (Modtype a) ->
(*	      warning ("This is an included module type");*)
	      let a' = handle_module_type path m a in
		[Element_included_module {(x) with im_module = Some (Modtype a')}]
	  | None -> 
(*	      warning ("Module couldn't be found");*)
	      add_renamed_module x.im_name m.m_name;
	      [y]
  and handle_module path m t      = (*{(t) with m_kind = handle_kind t.m_kind}*)
    let path' = (*if path = m.m_name then path else*) concat path (Name.simple t.m_name) in
(*      warning ("Entering module "^t.m_name^" in module "^m.m_name^" at path "^path^" => "^path');*)
      let result = 
	{(t) with m_kind = handle_kind path' t t.m_kind;
	   (*m_info = add_rename path t.m_info
	    ;*)m_name = path'} in
(*	warning ("Leaving module "^t.m_name^" as "^path');*)
	add_renamed_module t.m_name path';
	(match get_replacing t.m_info with
	  | None   -> ()
	  | Some r -> 
(*	      warning ("Additionally, "^r^" is replaced with "^path');*)
	      add_renamed_module r path');
	result
  and handle_module_type path m (t:Odoc_module.t_module_type) =
    let path' = (*if path = m.m_name then path else*) concat path (Name.simple t.mt_name) in
(*      warning ("Entering module type "^t.mt_name^" in module "^m.m_name^" at path "^path^" => "^path');*)
      let result = 
	{(t) with mt_kind = (match t.mt_kind with
	   | None -> None
	   | Some kind -> Some (handle_type_kind path' m kind));
	   (*mt_info = if path' <> t.mt_name then add_rename path  t.mt_info else t.mt_info
	    ;*)mt_name = path'} in
(*	warning ("Leaving module type "^t.mt_name^" as "^path');*)
	(*Hashtbl.add all_renamed_module_types path' result;*)
	add_renamed_module_type t.mt_name path';
	result
  and handle_alias path m (t:module_alias) : module_alias     = (*Module [m] is an alias to [t.ma_module]*)
    match t.ma_module with
      | None         -> (*warning ("module "^t.ma_name^" not resolved in cross-reference stage");*) t
      | Some (Mod a) -> 
	  (*warning ("module "^a.m_name^" marked for renaming as "^path);*)
	  add_renamed_module a.m_name path;
	  let info = Odoc_merge.merge_info_opt Odoc_types.all_merge_options m.m_info a.m_info
	  in m.m_info <- info;
	  let a' = {(a) with m_kind = handle_kind path m a.m_kind; m_info = info} in
	    {(t) with ma_module = Some (Mod a')}
      | Some (Modtype a) ->
(*	  warning ("module type "^a.mt_name^" marked for renaming as "^path);*)
	  add_renamed_module_type a.mt_name path;
	  let info = Odoc_merge.merge_info_opt Odoc_types.all_merge_options m.m_info a.mt_info in
	  let a' = match a.mt_kind with
	    | None      -> a
	    | Some kind -> {(a) with mt_kind = Some (handle_type_kind path m kind); mt_info = info} in
	    {(t) with ma_module = Some (Modtype a')}
  and handle_type_kind path m :module_type_kind -> module_type_kind   = function
    | Module_type_struct x      -> Module_type_struct (List.flatten (List.map (handle_module_element path m) x))
    | Module_type_functor (p, x)-> Module_type_functor (p, handle_type_kind path m x)
    | Module_type_alias x       -> Module_type_alias (handle_type_alias path m x)
    | Module_type_with (k, s)   -> Module_type_with (handle_type_kind path m k, s)
  and handle_type_alias path m t =  match t.mta_module with
      | None        -> (*warning ("module type "^t.mta_name^" not resolved in cross-reference stage");*) t
      | Some a      ->
	  (*warning ("module type "^a.mt_name^" renamed "^(concat m.m_name a.mt_name));*)
	  (*if a.mt_info <> None then m.m_info <- a.mt_info;*)
	  add_renamed_module_type a.mt_name path;
	  let info = Odoc_merge.merge_info_opt Odoc_types.all_merge_options m.m_info a.mt_info in
	  {(t) with mta_module = Some ({(a) with mt_name = concat m.m_name a.mt_name; mt_info = info})}
  in
  (*let first_pass = List.map (fun m -> 
			       if Name.father m.m_name <> "" then 
				 (
				   warning ("Will deal with module "^m.m_name^" later");
				   m (*Toplevel module*)
				 )
			       else 
				 (
				   warning ("Diving at module "^m.m_name);
				   {(m) with m_kind = handle_kind m m.m_kind}
				 )
			    )modules in
    List.map (fun m -> m) first_pass*)

  (*let dependencies = List.fold_left (fun acc m -> acc @ m.m_top_deps) [] modules in
    List.iter (fun x -> *)
  (*1. Find root modules, i.e. modules which are neither included nor aliased*)
  let roots = Hashtbl.create 100 in
    List.iter (fun x -> if Name.father x.m_name = "" then Hashtbl.add roots x.m_name x) modules;
    List.iter (fun x -> 
		    begin
(*		      warning("Dependencies of module "^x.m_name^":"); *)
		      List.iter (fun y -> (*warning(" removing "^y);*)
				   Hashtbl.remove roots y
				) x.m_top_deps
		    end)  modules;
    Hashtbl.iter (fun name _ -> warning ("Root: "^name)) roots;
      (*2. Dive into these*)
    let rewritten = Hashtbl.fold (fun name contents acc ->
		    (*warning ("Diving at module "^name);*)
		    {(contents) with m_kind = handle_kind name contents contents.m_kind}::acc
		 ) roots [] in
      (*warning ("New list of modules:");*)
      let result =  Search.modules rewritten in
(*      List.iter (fun x -> warning ("  "^x.m_name)) result;*)
(*Second pass: walk through references*)
	(*warning ("List of renamings:");
	Hashtbl.iter (fun k x -> warning (" "^k^" => "^x)) all_renamed_modules;*)
	(result, all_renamed_modules)


let find_renaming renamings original = 
  let rec aux s suffix = 
    if String.length s = 0 then 
      (
	warning ("Name '"^original^"' remains unchanged");
	suffix
      )
    else 
      let renaming = 
	try  Some (Hashtbl.find renamings s)
	with Not_found -> None
      in match renaming with
	| None -> 
	    let father = Name.father s              in
	    let son    = Name.get_relative father s in
	      aux father (concat son suffix)
	| Some r -> (*We have found a substitution, it should be over*)
	    let result = concat r suffix in
	      warning ("We have a renaming of "^s^" to "^r);
	      warning ("Name "^original^" should actually lead to "^result);
	      result
  in aux original ""    


let bs = Buffer.add_string
let bp = Printf.bprintf
let opt = Odoc_info.apply_opt
let string_of_bool b = if b then "true" else "false"

let name_substitutions : (string, string) Hashtbl.t = Hashtbl.create 100

class batlib_generator =
  object(self)
    inherit Odoc_html.html as super

    val mutable renamings : (string, string) Hashtbl.t = Hashtbl.create 0      

    method html_of_module b ?(info=true) ?(complete=true) ?(with_link=true) m =
      let name = m.m_name in
      let (html_file, _) = Naming.html_files name in
      let father = Name.father name in
      bs b "<pre>";
      bs b ((self#keyword "module")^" ");
      (
       if with_link then
         bp b "<a href=\"%s\">%s</a>" html_file (*(Name.simple name)*)name
       else
         bs b (*(Name.simple name)*)name
      );
      (
       match m.m_kind with
         Module_functor _ when !Odoc_info.Args.html_short_functors  ->
           ()
       | _ -> bs b ": "
      );
      self#html_of_module_kind b father ~modu: m m.m_kind;
      bs b "</pre>";
      if info then
        (
         if complete then
           self#html_of_info ~indent: false
         else
           self#html_of_info_first_sentence
        ) b m.m_info
      else
        ()


    method html_of_Ref b name ref_opt =
      warning ("printing reference to "^name);
      super#html_of_Ref b (find_renaming renamings name) ref_opt


      (**Replace references to [string] with [String.t],
	 [list] with [List.t] etc.

	 Override of [super#create_fully_qualified_idents_links]*)
    method create_fully_qualified_idents_links m_name s =
	(** Replace a complete path with a URL to that path*)
      let handle_qualified_name original_type_name = 
	let renamed_type_name  = find_renaming renamings original_type_name in
	  let rel     = Name.get_relative m_name renamed_type_name in
	  let s_final = Odoc_info.apply_if_equal
	    Odoc_info.use_hidden_modules
	    renamed_type_name
	    rel
	  in
	    if (Odoc_html.StringSet.mem original_type_name known_types_names ||
		  Odoc_html.StringSet.mem renamed_type_name known_types_names )
	    then "<a href=\""^(Naming.complete_target Naming.mark_type renamed_type_name)^"\">"^s_final^"</a>"
	    else(
              if (Odoc_html.StringSet.mem original_type_name known_classes_names ||
		    Odoc_html.StringSet.mem renamed_type_name known_classes_names)
	      then let (html_file, _) = Naming.html_files renamed_type_name in
		"<a href=\""^html_file^"\">"^s_final^"</a>"
              else s_final)
		(**Replace primitive type names with links to their representation module*)
      in let handle_word str_t = 
	let result = 
	  let (before,match_s) = (Str.matched_group 1 str_t, Str.matched_group 2 str_t) in
	    try
	      let link = List.assoc match_s primitive_types_names in
		(*let text = before^(end_of_name link) in*)
		before^"<a href=\""^(Naming.complete_target Naming.mark_type link)^"\">"^
			 match_s^"</a>"
		  (*(handle_qualified_name link)*)
	    with Not_found -> Str.matched_string str_t
	in result
      in
      let s2 = Str.global_substitute (*Substitute fully qualified names*)
	(Str.regexp "\\([A-Z]\\([a-zA-Z_'0-9]\\)*\\.\\)+\\([a-z][a-zA-Z_'0-9]*\\)")
	(fun str_t -> handle_qualified_name (Str.matched_string str_t))
	s 
      in
      let s3 = Str.global_substitute (*Substitute fully qualified names*)
	(Str.regexp "\\([^.a-zA-Z]\\|^\\)\\([a-z0-9]+\\)")
	handle_word
	s2
      in s3



    method generate modules =
      match !Odoc_args.dump with
	| Some l -> 
	    Odoc_info.verbose "[Internal representation stage, no readable output generated yet]";
	    ()
	| None   -> 
	    Odoc_info.verbose "[Final stage, generating html pages]";
	    (*Pre-process every module*)
	    let everything        = Search.modules modules in
	    let (rewritten_modules, renamed_modules) = rebuild_structure everything in
	      renamings <- renamed_modules;
	      super#generate rewritten_modules



    method html_of_replace _ = warning "REPLACE"; ""

    initializer
      tag_functions <- ("replace", self#html_of_replace) :: tag_functions

  end;;

let set_batlib_doc_generator () =
  let doc_generator = ((new batlib_generator) :> Args.doc_generator) in
    Args.set_doc_generator (Some doc_generator)

let _ =
  Odoc_args.verbose := true;
  set_batlib_doc_generator ();
  Args.add_option ("-html", Arg.Unit 
		     (fun _ -> Odoc_info.verbose "Deactivating built-in html generator";
			set_batlib_doc_generator())
		     , "<workaround for ocamldoc adding -html even when we don't want to>") 

(*    method html_of_module_comment b text =
      assert false

    method html_of_included_module b im =
      assert false;
      verbose ("Handling [include "^im.im_name^"]");
      match im.im_module with
	| None   ->    (*Keep default behavior.*)
	    warning ("Module inclusion of "^im.im_name^" unknown, keeping default behavior");
	    super#html_of_included_module b im
	| Some i ->    (*Let's inline the contents!*)
	    super#html_of_info b im.im_info;
	    match i with
	      | Mod m -> 
		  warning ("Module inclusion of "^im.im_name^" is a a struct, inlining");
		  super#html_of_module_kind b (Name.father m.m_name) ~modu:m m.m_kind
	      | _     -> 
		  warning ("Module inclusion of "^im.im_name^" is a signature, keeping default behavior");
		  super#html_of_included_module b im*)

(*    method html_of_Ref b name ref_opt =
      warning ("printing reference to "^name)

    method html_of_value b v = 
      warning ("Printing value "^string_of_value v);
      super#html_of_value b v*)

(*    method generate_for_module pre post modu =
      let name = 
	try Hashtbl.find name_substitutions modu.m_name
	with Not_found -> modu.m_name
      in warning ("In module generation, name "^modu.m_name^" becomes "^name);
      try
        Odoc_info.verbose ("Generate for module "^name);
        let (html_file, _) = Naming.html_files name in
        let type_file = Naming.file_type_module_complete_target name in
        let code_file = Naming.file_code_module_complete_target name in
        let chanout = open_out (Filename.concat !Args.target_dir html_file) in
        let b = Buffer.create 1000 in
        let pre_name = opt (fun m -> m.m_name) pre in
        let post_name = opt (fun m -> m.m_name) post in
        bs b doctype ;
        bs b "<html>\n";
        self#print_header b
          ~nav: (Some (pre_name, post_name, name))
          ~comments: (Module.module_comments modu)
          (self#inner_title name);
        bs b "<body>\n" ;
        self#print_navbar b pre_name post_name name ;
        bs b "<center><h1>";
        if modu.m_text_only then
          bs b name
        else
          (
           bs b
             (
              if Module.module_is_functor modu then
                Odoc_messages.functo
              else
                Odoc_messages.modul
             );
           bp b " <a href=\"%s\">%s</a>" type_file name;
           (
            match modu.m_code with
              None -> ()
            | Some _ -> bp b " (<a href=\"%s\">.ml</a>)" code_file
           )
          );
        bs b "</h1></center>\n<br>\n";

        if not modu.m_text_only then self#html_of_module b ~with_link: false modu;

        (* parameters for functors *)
        self#html_of_module_parameter_list b
          (Name.father name)
          (Module.module_parameters modu);

        (* a horizontal line *)
        if not modu.m_text_only then bs b "<hr width=\"100%\">\n";

        (* module elements *)
        List.iter
          (self#html_of_module_element b (Name.father name))
          (Module.module_elements modu);

        bs b "</body></html>";
        Buffer.output_buffer chanout b;
        close_out chanout;

        (* generate html files for submodules *)
        self#generate_elements  self#generate_for_module (Module.module_modules modu);
        (* generate html files for module types *)
        self#generate_elements  self#generate_for_module_type (Module.module_module_types modu);
        (* generate html files for classes *)
        self#generate_elements  self#generate_for_class (Module.module_classes modu);
        (* generate html files for class types *)
        self#generate_elements  self#generate_for_class_type (Module.module_class_types modu);

        (* generate the file with the complete module type *)
        self#output_module_type
          name
          (Filename.concat !Args.target_dir type_file)
          modu.m_type;

        match modu.m_code with
          None -> ()
        | Some code ->
            self#output_code
              name
              (Filename.concat !Args.target_dir code_file)
              code
      with
        Sys_error s ->
          raise (Failure s)*)