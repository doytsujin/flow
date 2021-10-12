(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

module Ast = Flow_ast
module LMap = Loc_collections.LocMap
module LSet = Loc_collections.LocSet
open Insert_type_utils

module DeclarationAnnotations = struct
  let declaration_locs_of_constrained_write_error cctx error =
    let tables = Context.aloc_tables (Codemod_context.Typed.context cctx) in
    let rec find_constrained_writes op =
      let open Type in
      match op with
      | Frame (ConstrainedAssignment { declaration; _ }, op) ->
        LSet.add (ALoc.to_loc_with_tables tables declaration) (find_constrained_writes op)
      | Op (Speculation op)
      | Frame (_, op) ->
        find_constrained_writes op
      | _ -> LSet.empty
    in
    let msg = Flow_error.msg_of_error error in
    let use_op_opt = Error_message.util_use_op_of_msg None (fun op _ -> Some op) msg in
    Base.Option.value_map ~f:find_constrained_writes ~default:LSet.empty use_op_opt
end

module ErrorStats = struct
  type t = { num_total_errors: int }

  let empty = { num_total_errors = 0 }

  let combine c1 c2 = { num_total_errors = c1.num_total_errors + c2.num_total_errors }

  let serialize s =
    let open Utils_js in
    [spf "total_errors: %d" s.num_total_errors]

  let report s = [string_of_row ~indent:2 "Number of constrained write errors" s.num_total_errors]
end

module Codemod_declaration_annotator = Codemod_annotator.Make (ErrorStats)
module Acc = Insert_type_utils.Acc (ErrorStats)

let mapper ~preserve_literals ~max_type_size ~default_any (cctx : Codemod_context.Typed.t) =
  let { Codemod_context.Typed.file_sig; docblock; metadata; options; _ } = cctx in
  let imports_react = Insert_type_imports.ImportsHelper.imports_react file_sig in
  let metadata = Context.docblock_overrides docblock metadata in
  let { Context.strict; strict_local; _ } = metadata in
  let lint_severities =
    if strict || strict_local then
      StrictModeSettings.fold
        (fun lint_kind lint_severities ->
          LintSettings.set_value lint_kind (Severity.Err, None) lint_severities)
        (Options.strict_mode options)
        (Options.lint_severities options)
    else
      Options.lint_severities options
  in
  let suppress_types = Options.suppress_types options in
  let exact_by_default = Options.exact_by_default options in
  let flowfixme_ast = Builtins.flowfixme_ast ~lint_severities ~suppress_types ~exact_by_default in
  object (this)
    inherit
      Codemod_declaration_annotator.mapper
        ~max_type_size
        ~exact_by_default
        ~lint_severities
        ~suppress_types
        ~imports_react
        ~preserve_literals
        ~default_any
        cctx as super

    val mutable loc_error_map = LMap.empty

    method private post_run () =
      this#add_unannotated_loc_warnings loc_error_map;
      ErrorStats.{ num_total_errors = LMap.cardinal loc_error_map }

    method! variable_declarator_pattern ~kind ((ploc, patt) : ('loc, 'loc) Ast.Pattern.t) =
      let get_annot ty annot =
        let f loc _annot ty' = this#annotate_node loc ty' (fun a -> Ast.Type.Available a) in
        let error _ = Ast.Type.Available (Loc.none, flowfixme_ast) in
        this#opt_annotate ~f ~error ~expr:None ploc ty annot
      in

      if LMap.mem ploc loc_error_map then (
        let ty_result = Codemod_annotator.get_ty cctx ~preserve_literals ~max_type_size ploc in
        match patt with
        | Ast.Pattern.Object Ast.Pattern.Object.{ annot; properties; comments } ->
          let annot' = get_annot ty_result annot in
          (ploc, Ast.Pattern.Object Ast.Pattern.Object.{ annot = annot'; properties; comments })
        | Ast.Pattern.Array Ast.Pattern.Array.{ annot; elements; comments } ->
          let annot' = get_annot ty_result annot in
          (ploc, Ast.Pattern.Array Ast.Pattern.Array.{ annot = annot'; elements; comments })
        | Ast.Pattern.Identifier Ast.Pattern.Identifier.{ annot; name; optional } ->
          let annot' = get_annot ty_result annot in
          (ploc, Ast.Pattern.Identifier Ast.Pattern.Identifier.{ annot = annot'; name; optional })
        | Ast.Pattern.Expression _ ->
          (* No such thing as a pattern expression *)
          this#update_acc (fun acc -> Acc.error acc ploc Error.Unsupported_error_kind);
          codemod_error_locs <- LSet.add ploc codemod_error_locs;
          (ploc, patt)
      ) else
        super#variable_declarator_pattern ~kind (ploc, patt)

    method! program prog =
      let errors = Context.errors @@ Codemod_context.Typed.context cctx in
      loc_error_map <-
        Flow_error.ErrorSet.fold
          (fun error ->
            LSet.fold
              (fun loc -> LMap.add loc ())
              (DeclarationAnnotations.declaration_locs_of_constrained_write_error cctx error))
          errors
          LMap.empty;
      if LMap.is_empty loc_error_map then
        prog
      else
        super#program prog
  end