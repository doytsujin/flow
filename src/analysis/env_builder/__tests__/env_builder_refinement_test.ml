(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open Test_utils
module LocMap = Loc_collections.LocMap
module LocSet = Loc_collections.LocSet

let print_values refinement_of_id =
  let open Name_resolver.With_Loc.Env_api in
  let rec print_value write_loc =
    match write_loc with
    | Uninitialized _ -> "(uninitialized)"
    | Projection -> "projection"
    | UninitializedClass { def; _ } ->
      let loc = Reason.poly_loc_of_reason def in
      Utils_js.spf
        "(uninitialized class) %s: (%s)"
        (L.debug_to_string loc)
        Reason.(desc_of_reason def |> string_of_desc)
    | Write reason ->
      let loc = Reason.poly_loc_of_reason reason in
      Utils_js.spf
        "%s: (%s)"
        (L.debug_to_string loc)
        Reason.(desc_of_reason reason |> string_of_desc)
    | Refinement { refinement_id; writes } ->
      let refinement = refinement_of_id refinement_id in
      let refinement_str = show_refinement_kind_without_locs (snd refinement) in
      let writes_str = String.concat "," (List.map print_value writes) in
      Printf.sprintf "{refinement = %s; writes = %s}" refinement_str writes_str
    | Global name -> "Global " ^ name
    | Unreachable _ -> "unreachable"
  in
  fun values ->
    let kvlist = L.LMap.bindings values in
    let strlist =
      Base.List.map
        ~f:(fun (read_loc, write_locs) ->
          Printf.sprintf
            "%s => {\n    %s\n  }"
            (L.debug_to_string read_loc)
            (String.concat ",\n    " @@ Base.List.map ~f:print_value write_locs))
        kvlist
    in
    Printf.printf "[\n  %s]" (String.concat ";\n  " strlist)

(* TODO: ocamlformat mangles the ppx syntax. *)
[@@@ocamlformat "disable=true"]

let print_ssa_test contents =
  let refined_reads, refinement_of_id = Name_resolver.With_Loc.program () (parse contents) in
  print_values refinement_of_id refined_reads

let%expect_test "logical_expr" =
  print_ssa_test {|let x = null;
let y = null;
(x && (y = x)) + x|};
  [%expect {|
    [
      (3, 1) to (3, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (3, 11) to (3, 12) => {
        {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
      };
      (3, 17) to (3, 18) => {
        (1, 4) to (1, 5): (`x`)
      }] |}]

let%expect_test "logical_expr_successive" =
  print_ssa_test {|let x = null;
x && (x && x)|};
  [%expect {|
    [
      (2, 0) to (2, 1) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 6) to (2, 7) => {
        {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
      };
      (2, 11) to (2, 12) => {
        {refinement = Truthy; writes = {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}}
      }] |}]

let%expect_test "logical_or" =
  print_ssa_test {|let x = null;
x || x|};
  [%expect {|
    [
      (2, 0) to (2, 1) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 5) to (2, 6) => {
        {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "logical_nc_and" =
  print_ssa_test {|let x = null;
(x ?? x) && x|};
  [%expect{|
    [
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 6) to (2, 7) => {
        {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
      };
      (2, 12) to (2, 13) => {
        {refinement = Or (And (Not (Maybe), Truthy), Truthy); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "logical_nc_no_key" =
  print_ssa_test {|let x = null;
((x != null) ?? x) && x|};
  [%expect {|
    [
      (2, 2) to (2, 3) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 16) to (2, 17) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 22) to (2, 23) => {
        {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "logical_nested_right" =
  print_ssa_test {|let x = null;
x || (x || x)|};
  [%expect {|
    [
      (2, 0) to (2, 1) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 6) to (2, 7) => {
        {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}
      };
      (2, 11) to (2, 12) => {
        {refinement = Not (Truthy); writes = {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}}
      }] |}]

let%expect_test "logical_nested" =
  print_ssa_test {|let x = null;
(x || (x != null)) && x|};
  [%expect {|
    [
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 7) to (2, 8) => {
        {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}
      };
      (2, 22) to (2, 23) => {
        {refinement = Or (Truthy, Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "logical_nested2" =
  print_ssa_test {|let x = null;
(x && x) || (x && x)|};
  [%expect {|
    [
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 6) to (2, 7) => {
        {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
      };
      (2, 13) to (2, 14) => {
        {refinement = Not (And (Truthy, Truthy)); writes = (1, 4) to (1, 5): (`x`)}
      };
      (2, 18) to (2, 19) => {
        {refinement = Truthy; writes = {refinement = Not (And (Truthy, Truthy)); writes = (1, 4) to (1, 5): (`x`)}}
      }] |}]

let%expect_test "assignment_truthy" =
  print_ssa_test {|let x = null;
(x = null) && x|};
  [%expect {|
    [
      (2, 14) to (2, 15) => {
        {refinement = Truthy; writes = (2, 1) to (2, 2): (`x`)}
      }] |}]

let%expect_test "eq_null" =
  print_ssa_test {|let x = null;
(x == null) && x|};
  [%expect {|
    [
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 15) to (2, 16) => {
        {refinement = Maybe; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "neq_null" =
  print_ssa_test {|let x = null;
(x != null) && x|};
  [%expect {|
    [
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 15) to (2, 16) => {
        {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "strict_eq_null" =
  print_ssa_test {|let x = null;
(x === null) && x|};
  [%expect {|
    [
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 16) to (2, 17) => {
        {refinement = Null; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "strict_neq_null" =
  print_ssa_test {|let x = null;
(x !== null) && x|};
  [%expect {|
    [
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 16) to (2, 17) => {
        {refinement = Not (Null); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "eq_undefined" =
  print_ssa_test {|let x = undefined;
(x == undefined) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 6) to (2, 15) => {
        Global undefined
      };
      (2, 20) to (2, 21) => {
        {refinement = Maybe; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "neq_undefined" =
  print_ssa_test {|let x = undefined;
(x != undefined) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 6) to (2, 15) => {
        Global undefined
      };
      (2, 20) to (2, 21) => {
        {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "strict_eq_undefined" =
  print_ssa_test {|let x = undefined;
(x === undefined) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 7) to (2, 16) => {
        Global undefined
      };
      (2, 21) to (2, 22) => {
        {refinement = Undefined; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "strict_neq_undefined" =
  print_ssa_test {|let x = undefined;
(x !== undefined) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 7) to (2, 16) => {
        Global undefined
      };
      (2, 21) to (2, 22) => {
        {refinement = Not (Undefined); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "undefined_already_bound" =
  print_ssa_test {|let undefined = 3;
let x = null;
(x !== undefined) && x|};
  [%expect {|
    [
      (3, 1) to (3, 2) => {
        (2, 4) to (2, 5): (`x`)
      };
      (3, 7) to (3, 16) => {
        (1, 4) to (1, 13): (`undefined`)
      };
      (3, 21) to (3, 22) => {
        (2, 4) to (2, 5): (`x`)
      }] |}]

let%expect_test "eq_void" =
  print_ssa_test {|let x = undefined;
(x == void 0) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 17) to (2, 18) => {
        {refinement = Maybe; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "neq_void" =
  print_ssa_test {|let x = undefined;
(x != void 0) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 17) to (2, 18) => {
        {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "strict_eq_void" =
  print_ssa_test {|let x = undefined;
(x === void 0) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 18) to (2, 19) => {
        {refinement = Undefined; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "strict_neq_void" =
  print_ssa_test {|let x = undefined;
(x !== void 0) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 18) to (2, 19) => {
        {refinement = Not (Undefined); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "instanceof" =
  print_ssa_test {|let x = undefined;
(x instanceof Object) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 14) to (2, 20) => {
        Global Object
      };
      (2, 25) to (2, 26) => {
        {refinement = instanceof; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "Array.isArray" =
  print_ssa_test {|let x = undefined;
(Array.isArray(x)) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 6) => {
        Global Array
      };
      (2, 15) to (2, 16) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 22) to (2, 23) => {
        {refinement = isArray; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "unary_negation" =
  print_ssa_test {|let x = undefined;
(!Array.isArray(x)) && x;
!x && x;
!(x || x) && x;|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 2) to (2, 7) => {
        Global Array
      };
      (2, 16) to (2, 17) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 23) to (2, 24) => {
        {refinement = Not (isArray); writes = (1, 4) to (1, 5): (`x`)}
      };
      (3, 1) to (3, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (3, 6) to (3, 7) => {
        {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}
      };
      (4, 2) to (4, 3) => {
        (1, 4) to (1, 5): (`x`)
      };
      (4, 7) to (4, 8) => {
        {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}
      };
      (4, 13) to (4, 14) => {
        {refinement = Not (Or (Truthy, Truthy)); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "typeof_bool" =
  print_ssa_test {|let x = undefined;
(typeof x == "boolean") && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 27) to (2, 28) => {
        {refinement = bool; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "not_typeof_bool" =
  print_ssa_test {|let x = undefined;
(typeof x != "boolean") && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 27) to (2, 28) => {
        {refinement = Not (bool); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "typeof_number" =
  print_ssa_test {|let x = undefined;
(typeof x == "number") && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = number; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "not_typeof_number" =
  print_ssa_test {|let x = undefined;
(typeof x != "number") && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = Not (number); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "typeof_function" =
  print_ssa_test {|let x = undefined;
(typeof x == "function") && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 28) to (2, 29) => {
        {refinement = function; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "not_typeof_function" =
  print_ssa_test {|let x = undefined;
(typeof x != "function") && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 28) to (2, 29) => {
        {refinement = Not (function); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "typeof_object" =
  print_ssa_test {|let x = undefined;
(typeof x == "object") && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = object; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "not_typeof_object" =
  print_ssa_test {|let x = undefined;
(typeof x != "object") && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = Not (object); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "typeof_string" =
  print_ssa_test {|let x = undefined;
(typeof x == "string") && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = string; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "not_typeof_string" =
  print_ssa_test {|let x = undefined;
(typeof x != "string") && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = Not (string); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "typeof_symbol" =
  print_ssa_test {|let x = undefined;
(typeof x == "symbol") && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = symbol; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "not_typeof_symbol" =
  print_ssa_test {|let x = undefined;
(typeof x != "symbol") && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = Not (symbol); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "typeof_bool_template" =
  print_ssa_test {|let x = undefined;
(typeof x == `boolean`) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 27) to (2, 28) => {
        {refinement = bool; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "not_typeof_bool_template" =
  print_ssa_test {|let x = undefined;
(typeof x != `boolean`) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 27) to (2, 28) => {
        {refinement = Not (bool); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "typeof_number_template" =
  print_ssa_test {|let x = undefined;
(typeof x == `number`) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = number; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "not_typeof_number_template" =
  print_ssa_test {|let x = undefined;
(typeof x != `number`) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = Not (number); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "typeof_function_template" =
  print_ssa_test {|let x = undefined;
(typeof x == `function`) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 28) to (2, 29) => {
        {refinement = function; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "not_typeof_function_template" =
  print_ssa_test {|let x = undefined;
(typeof x != `function`) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 28) to (2, 29) => {
        {refinement = Not (function); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "typeof_object_template" =
  print_ssa_test {|let x = undefined;
(typeof x == `object`) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = object; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "not_typeof_object_template" =
  print_ssa_test {|let x = undefined;
(typeof x != `object`) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = Not (object); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "typeof_string_template" =
  print_ssa_test {|let x = undefined;
(typeof x == `string`) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = string; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "not_typeof_string_template" =
  print_ssa_test {|let x = undefined;
(typeof x != `string`) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = Not (string); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "typeof_symbol_template" =
  print_ssa_test {|let x = undefined;
(typeof x == `symbol`) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = symbol; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "not_typeof_symbol_template" =
  print_ssa_test {|let x = undefined;
(typeof x != `symbol`) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 8) to (2, 9) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 26) to (2, 27) => {
        {refinement = Not (symbol); writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "singleton_bool" =
  print_ssa_test {|let x = undefined;
(x === true) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 16) to (2, 17) => {
        {refinement = true; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "singleton_str" =
  print_ssa_test {|let x = undefined;
(x === "str") && x|};
  [%expect{|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 17) to (2, 18) => {
        {refinement = str; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "singleton_str_template" =
  print_ssa_test {|let x = undefined;
(x === `str`) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 17) to (2, 18) => {
        {refinement = str; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "singleton_num" =
  print_ssa_test {|let x = undefined;
(x === 3) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 13) to (2, 14) => {
        {refinement = 3; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "singleton_num_neg" =
  print_ssa_test {|let x = undefined;
(x === -3) && x|};
  [%expect {|
    [
      (1, 8) to (1, 17) => {
        Global undefined
      };
      (2, 1) to (2, 2) => {
        (1, 4) to (1, 5): (`x`)
      };
      (2, 14) to (2, 15) => {
        {refinement = -3; writes = (1, 4) to (1, 5): (`x`)}
      }] |}]

let%expect_test "sentinel_lit" =
  print_ssa_test {|let x = undefined;
(x.foo === 3) && x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 1) to (2, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 17) to (2, 18) => {
          {refinement = SentinelR foo; writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "sentinel_lit_indexed " =
  print_ssa_test {|let x = undefined;
(x["foo"] === 3) && x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 1) to (2, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 20) to (2, 21) => {
          {refinement = SentinelR foo; writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "sentinel_nonlit" =
  print_ssa_test {|let x = undefined;
let y = undefined;
(x.foo === y) && x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 17) => {
          Global undefined
        };
        (3, 1) to (3, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 11) to (3, 12) => {
          (2, 4) to (2, 5): (`y`)
        };
        (3, 17) to (3, 18) => {
          {refinement = SentinelR foo; writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "sentinel_nonlit_indexed" =
  print_ssa_test {|let x = undefined;
let y = undefined;
(x["foo"] === y) && x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 17) => {
          Global undefined
        };
        (3, 1) to (3, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 14) to (3, 15) => {
          (2, 4) to (2, 5): (`y`)
        };
        (3, 20) to (3, 21) => {
          {refinement = SentinelR foo; writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "optional_chain_lit" =
  print_ssa_test {|let x = undefined;
(x?.foo === 3) && x|};
    [%expect{|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 1) to (2, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 18) to (2, 19) => {
          {refinement = And (SentinelR foo, Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "optional_chain_member_base" =
  print_ssa_test {|let x = undefined;
(x.foo?.bar === 3) && x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 1) to (2, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 22) to (2, 23) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "optional_chain_with_call" =
  print_ssa_test {|let x = undefined;
(x?.foo().bar === 3) && x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 1) to (2, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 24) to (2, 25) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "optional_multiple_chains" =
  print_ssa_test {|let x = undefined;
(x?.foo?.bar.baz?.qux === 3) && x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 1) to (2, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 32) to (2, 33) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "optional_base_call" =
  print_ssa_test {|let x = undefined;
(x?.().foo?.bar.baz?.qux === 3) && x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 1) to (2, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 35) to (2, 36) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "sentinel_standalone" =
  print_ssa_test {|let x = undefined;
x.foo && x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 0) to (2, 1) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 9) to (2, 10) => {
          {refinement = SentinelR foo; writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "optional_chain_standalone" =
  print_ssa_test {|let x = undefined;
x?.foo && x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 0) to (2, 1) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 10) to (2, 11) => {
          {refinement = And (SentinelR foo, Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "conditional_expression" =
  print_ssa_test {|let x = undefined;
(x ? x: x) && x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 1) to (2, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 5) to (2, 6) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        };
        (2, 8) to (2, 9) => {
          {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}
        };
        (2, 14) to (2, 15) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "conditional_throw" =
  print_ssa_test {|let x = undefined;
(x ? invariant() : x) && x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 1) to (2, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 5) to (2, 14) => {
          Global invariant
        };
        (2, 19) to (2, 20) => {
          {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}
        };
        (2, 25) to (2, 26) => {
          {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "conditional_throw2" =
  print_ssa_test {|let x = undefined;
(x ? x : invariant()) && x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 1) to (2, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 5) to (2, 6) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        };
        (2, 9) to (2, 18) => {
          Global invariant
        };
        (2, 25) to (2, 26) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "logical_throw_and" =
  print_ssa_test {|let x = undefined;
x && invariant();
x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 0) to (2, 1) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 5) to (2, 14) => {
          Global invariant
        };
        (3, 0) to (3, 1) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "logical_throw_or" =
  print_ssa_test {|let x = undefined;
x || invariant();
x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 0) to (2, 1) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 5) to (2, 14) => {
          Global invariant
        };
        (3, 0) to (3, 1) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "logical_throw_nc" =
  print_ssa_test {|let x = undefined;
x ?? invariant();
x|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 0) to (2, 1) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 5) to (2, 14) => {
          Global invariant
        };
        (3, 0) to (3, 1) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "logical_throw_reassignment" =
  print_ssa_test {|let x = undefined;
try {
  x ?? invariant(false, x = 3);
} finally {
  x;
}|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (3, 2) to (3, 3) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 7) to (3, 16) => {
          Global invariant
        };
        (5, 2) to (5, 3) => {
          (3, 24) to (3, 25): (`x`),
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "nested_logical_throw_and" =
  print_ssa_test {|let x = undefined;
(x && invariant()) && x;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 1) to (2, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 6) to (2, 15) => {
          Global invariant
        };
        (2, 22) to (2, 23) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        };
        (3, 0) to (3, 1) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "nested_logical_throw_or" =
  print_ssa_test {|let x = undefined;
(x || invariant()) && x;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 1) to (2, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 6) to (2, 15) => {
          Global invariant
        };
        (2, 22) to (2, 23) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        };
        (3, 0) to (3, 1) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "nested_logical_throw_nc" =
  print_ssa_test {|let x = undefined;
(x ?? invariant()) && x;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 1) to (2, 2) => {
          (1, 4) to (1, 5): (`x`)
        };
        (2, 6) to (2, 15) => {
          Global invariant
        };
        (2, 22) to (2, 23) => {
          {refinement = And (Not (Maybe), Truthy); writes = (1, 4) to (1, 5): (`x`)}
        };
        (3, 0) to (3, 1) => {
          {refinement = And (Not (Maybe), Truthy); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "if_else_statement" =
  print_ssa_test {|let x = undefined;
if (x) {
  x;
} else {
  x;
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 4) to (2, 5) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 2) to (3, 3) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        };
        (5, 2) to (5, 3) => {
          {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}
        };
        (7, 0) to (7, 1) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "if_no_else_statement" =
  print_ssa_test {|let x = undefined;
if (x) {
  x;
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 4) to (2, 5) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 2) to (3, 3) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        };
        (5, 0) to (5, 1) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "if_no_else_statement_with_assignment" =
  print_ssa_test {|let x = undefined;
if (x !== null) {
  x = null;
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 4) to (2, 5) => {
          (1, 4) to (1, 5): (`x`)
        };
        (5, 0) to (5, 1) => {
          (3, 2) to (3, 3): (`x`),
          {refinement = Not (Not (Null)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "if_throw_else_statement" =
  print_ssa_test {|let x = undefined;
if (x) {
  throw 'error';
} else {
  x;
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 4) to (2, 5) => {
          (1, 4) to (1, 5): (`x`)
        };
        (5, 2) to (5, 3) => {
          {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}
        };
        (7, 0) to (7, 1) => {
          {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "if_else_throw_statement" =
  print_ssa_test {|let x = undefined;
if (x) {
  x;
} else {
  throw 'error';
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 4) to (2, 5) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 2) to (3, 3) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        };
        (7, 0) to (7, 1) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "if_return_else_statement" =
  print_ssa_test {|function f() {
  let x = undefined;
  if (x) {
    return;
  } else {
    x;
  }
  x;
}
|};
    [%expect{|
      [
        (2, 10) to (2, 19) => {
          Global undefined
        };
        (3, 6) to (3, 7) => {
          (2, 6) to (2, 7): (`x`)
        };
        (6, 4) to (6, 5) => {
          {refinement = Not (Truthy); writes = (2, 6) to (2, 7): (`x`)}
        };
        (8, 2) to (8, 3) => {
          {refinement = Not (Truthy); writes = (2, 6) to (2, 7): (`x`)}
        }] |}]

let%expect_test "if_else_return_statement" =
  print_ssa_test {|function f() {
  let x = undefined;
  if (x) {
    x;
  } else {
    return;
  }
  x;
}
|};
    [%expect{|
      [
        (2, 10) to (2, 19) => {
          Global undefined
        };
        (3, 6) to (3, 7) => {
          (2, 6) to (2, 7): (`x`)
        };
        (4, 4) to (4, 5) => {
          {refinement = Truthy; writes = (2, 6) to (2, 7): (`x`)}
        };
        (8, 2) to (8, 3) => {
          {refinement = Truthy; writes = (2, 6) to (2, 7): (`x`)}
        }] |}]

let%expect_test "nested_if_else_statement" =
  print_ssa_test {|let x = undefined;
if (x) {
  if (x === null) {
    throw 'error';
  }
  x;
} else {
  if (x === null) {
    x;
  } else {
    throw 'error';
  }
  x;
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 4) to (2, 5) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 6) to (3, 7) => {
          {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}
        };
        (6, 2) to (6, 3) => {
          {refinement = Not (Null); writes = {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}}
        };
        (8, 6) to (8, 7) => {
          {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}
        };
        (9, 4) to (9, 5) => {
          {refinement = Null; writes = {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}}
        };
        (13, 2) to (13, 3) => {
          {refinement = Null; writes = {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}}
        };
        (15, 0) to (15, 1) => {
          {refinement = Not (Null); writes = {refinement = Truthy; writes = (1, 4) to (1, 5): (`x`)}},
          {refinement = Null; writes = {refinement = Not (Truthy); writes = (1, 4) to (1, 5): (`x`)}}
        }] |}]

let%expect_test "while" =
  print_ssa_test {|let x = undefined;
while (x != null) {
  x;
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 7) to (2, 8) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 2) to (3, 3) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
        };
        (5, 0) to (5, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "while_throw" =
  print_ssa_test {|let x = undefined;
while (x != null) {
  throw 'error';
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 7) to (2, 8) => {
          (1, 4) to (1, 5): (`x`)
        };
        (5, 0) to (5, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "while_break_with_control_flow_writes" =
  print_ssa_test {|let x = undefined;
let y = undefined;
while (x != null) {
  if (y == null) {
    break;
  }
  y;
}
y;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 17) => {
          Global undefined
        };
        (3, 7) to (3, 8) => {
          (1, 4) to (1, 5): (`x`)
        };
        (4, 6) to (4, 7) => {
          (2, 4) to (2, 5): (`y`)
        };
        (7, 2) to (7, 3) => {
          {refinement = Not (Maybe); writes = (2, 4) to (2, 5): (`y`)}
        };
        (9, 0) to (9, 1) => {
          (2, 4) to (2, 5): (`y`),
          {refinement = Maybe; writes = (2, 4) to (2, 5): (`y`)},
          {refinement = Not (Maybe); writes = (2, 4) to (2, 5): (`y`)}
        };
        (10, 0) to (10, 1) => {
          (1, 4) to (1, 5): (`x`),
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "while_with_runtime_writes" =
  print_ssa_test {|let x = undefined;
let y = undefined;
while (x != null) {
  if (y == null) {
    x = 2;
  }
  y;
}
y;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 17) => {
          Global undefined
        };
        (3, 7) to (3, 8) => {
          (1, 4) to (1, 5): (`x`)
        };
        (4, 6) to (4, 7) => {
          (2, 4) to (2, 5): (`y`)
        };
        (7, 2) to (7, 3) => {
          (2, 4) to (2, 5): (`y`)
        };
        (9, 0) to (9, 1) => {
          (2, 4) to (2, 5): (`y`)
        };
        (10, 0) to (10, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`),(5, 4) to (5, 5): (`x`)}
        }] |}]

let%expect_test "while_continue" =
  print_ssa_test {|let x = undefined;
while (x != null) {
  continue;
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 7) to (2, 8) => {
          (1, 4) to (1, 5): (`x`)
        };
        (5, 0) to (5, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "while_continue_with_control_flow_writes" =
  print_ssa_test {|let x = undefined;
let y = undefined;
while (x != null) {
  if (y == null) {
    continue;
  }
  y;
}
y;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 17) => {
          Global undefined
        };
        (3, 7) to (3, 8) => {
          (1, 4) to (1, 5): (`x`)
        };
        (4, 6) to (4, 7) => {
          (2, 4) to (2, 5): (`y`)
        };
        (7, 2) to (7, 3) => {
          {refinement = Not (Maybe); writes = (2, 4) to (2, 5): (`y`)}
        };
        (9, 0) to (9, 1) => {
          (2, 4) to (2, 5): (`y`),
          {refinement = Maybe; writes = (2, 4) to (2, 5): (`y`)},
          {refinement = Not (Maybe); writes = (2, 4) to (2, 5): (`y`)}
        };
        (10, 0) to (10, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "while_phi_node_refinement" =
  print_ssa_test {|let x = undefined;
while (x != null) {
  if (x === 3) {
    continue;
  }
  x;
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 7) to (2, 8) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 6) to (3, 7) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
        };
        (6, 2) to (6, 3) => {
          {refinement = Not (3); writes = {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}}
        };
        (8, 0) to (8, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`),{refinement = 3; writes = (1, 4) to (1, 5): (`x`)},{refinement = Not (3); writes = (1, 4) to (1, 5): (`x`)}}
        }] |}]

let%expect_test "do_while" =
  print_ssa_test {|let x = undefined;
do {
  x;
} while (x != null);
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (3, 2) to (3, 3) => {
          (1, 4) to (1, 5): (`x`)
        };
        (4, 9) to (4, 10) => {
          (1, 4) to (1, 5): (`x`)
        };
        (5, 0) to (5, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "do_while_break_with_control_flow_writes" =
  print_ssa_test {|let x = undefined;
let y = undefined;
do {
  if (y == null) {
    break;
  }
  y;
} while (x != null);
y;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 17) => {
          Global undefined
        };
        (4, 6) to (4, 7) => {
          (2, 4) to (2, 5): (`y`)
        };
        (7, 2) to (7, 3) => {
          {refinement = Not (Maybe); writes = (2, 4) to (2, 5): (`y`)}
        };
        (8, 9) to (8, 10) => {
          (1, 4) to (1, 5): (`x`)
        };
        (9, 0) to (9, 1) => {
          {refinement = Maybe; writes = (2, 4) to (2, 5): (`y`)},
          {refinement = Not (Maybe); writes = (2, 4) to (2, 5): (`y`)}
        };
        (10, 0) to (10, 1) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "do_while_with_runtime_writes" =
  print_ssa_test {|let x = undefined;
let y = undefined;
do {
  if (y == null) {
    x = 2;
  }
  y;
} while (x != null);
y;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 17) => {
          Global undefined
        };
        (4, 6) to (4, 7) => {
          (2, 4) to (2, 5): (`y`)
        };
        (7, 2) to (7, 3) => {
          (2, 4) to (2, 5): (`y`)
        };
        (8, 9) to (8, 10) => {
          (1, 4) to (1, 5): (`x`),
          (5, 4) to (5, 5): (`x`)
        };
        (9, 0) to (9, 1) => {
          (2, 4) to (2, 5): (`y`)
        };
        (10, 0) to (10, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`),(5, 4) to (5, 5): (`x`)}
        }] |}]

let%expect_test "do_while_continue" =
  print_ssa_test {|let x = undefined;
do {
  continue;
} while (x != null);
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (4, 9) to (4, 10) => {
          (1, 4) to (1, 5): (`x`)
        };
        (5, 0) to (5, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "do_while_continue_with_control_flow_writes" =
  print_ssa_test {|let x = undefined;
let y = undefined;
do {
  if (y == null) {
    continue;
  }
  y;
} while (x != null);
y;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 17) => {
          Global undefined
        };
        (4, 6) to (4, 7) => {
          (2, 4) to (2, 5): (`y`)
        };
        (7, 2) to (7, 3) => {
          {refinement = Not (Maybe); writes = (2, 4) to (2, 5): (`y`)}
        };
        (8, 9) to (8, 10) => {
          (1, 4) to (1, 5): (`x`)
        };
        (9, 0) to (9, 1) => {
          {refinement = Maybe; writes = (2, 4) to (2, 5): (`y`)},
          {refinement = Not (Maybe); writes = (2, 4) to (2, 5): (`y`)}
        };
        (10, 0) to (10, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "do_while_phi_node_refinement" =
  print_ssa_test {|let x = undefined;
do {
  if (x === 3) {
    continue;
  }
  x;
} while (x != null);
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (3, 6) to (3, 7) => {
          (1, 4) to (1, 5): (`x`)
        };
        (6, 2) to (6, 3) => {
          {refinement = Not (3); writes = (1, 4) to (1, 5): (`x`)}
        };
        (7, 9) to (7, 10) => {
          {refinement = 3; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = Not (3); writes = (1, 4) to (1, 5): (`x`)}
        };
        (8, 0) to (8, 1) => {
          {refinement = Not (Not (Maybe)); writes = {refinement = 3; writes = (1, 4) to (1, 5): (`x`)},{refinement = Not (3); writes = (1, 4) to (1, 5): (`x`)}}
        }] |}]

let%expect_test "for_no_init_no_update" =
  print_ssa_test {|let x = undefined;
for (;x != null;) {
  x;
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 6) to (2, 7) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 2) to (3, 3) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
        };
        (5, 0) to (5, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "for_no_init_no_update_throw" =
  print_ssa_test {|let x = undefined;
for (;x != null;) {
  throw 'error';
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 6) to (2, 7) => {
          (1, 4) to (1, 5): (`x`)
        };
        (5, 0) to (5, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "for_no_init_no_update_break_with_control_flow_writes" =
  print_ssa_test {|let x = undefined;
let y = undefined;
for (; x != null; ) {
  if (y == null) {
    break;
  }
  y;
}
y;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 17) => {
          Global undefined
        };
        (3, 7) to (3, 8) => {
          (1, 4) to (1, 5): (`x`)
        };
        (4, 6) to (4, 7) => {
          (2, 4) to (2, 5): (`y`)
        };
        (7, 2) to (7, 3) => {
          {refinement = Not (Maybe); writes = (2, 4) to (2, 5): (`y`)}
        };
        (9, 0) to (9, 1) => {
          (2, 4) to (2, 5): (`y`),
          {refinement = Maybe; writes = (2, 4) to (2, 5): (`y`)},
          {refinement = Not (Maybe); writes = (2, 4) to (2, 5): (`y`)}
        };
        (10, 0) to (10, 1) => {
          (1, 4) to (1, 5): (`x`),
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "for_no_init_no_update_with_runtime_writes" =
  print_ssa_test {|let x = undefined;
let y = undefined;
for (;x != null;) {
  if (y == null) {
    x = 2;
  }
  y;
}
y;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 17) => {
          Global undefined
        };
        (3, 6) to (3, 7) => {
          (1, 4) to (1, 5): (`x`)
        };
        (4, 6) to (4, 7) => {
          (2, 4) to (2, 5): (`y`)
        };
        (7, 2) to (7, 3) => {
          (2, 4) to (2, 5): (`y`)
        };
        (9, 0) to (9, 1) => {
          (2, 4) to (2, 5): (`y`)
        };
        (10, 0) to (10, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`),(5, 4) to (5, 5): (`x`)}
        }] |}]

let%expect_test "for_no_init_no_update_continue" =
  print_ssa_test {|let x = undefined;
for (; x != null; ) {
  continue;
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 7) to (2, 8) => {
          (1, 4) to (1, 5): (`x`)
        };
        (5, 0) to (5, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "for_no_init_no_update_continue_with_control_flow_writes" =
  print_ssa_test {|let x = undefined;
let y = undefined;
for (;x != null;) {
  if (y == null) {
    continue;
  }
  y;
}
y;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 17) => {
          Global undefined
        };
        (3, 6) to (3, 7) => {
          (1, 4) to (1, 5): (`x`)
        };
        (4, 6) to (4, 7) => {
          (2, 4) to (2, 5): (`y`)
        };
        (7, 2) to (7, 3) => {
          {refinement = Not (Maybe); writes = (2, 4) to (2, 5): (`y`)}
        };
        (9, 0) to (9, 1) => {
          (2, 4) to (2, 5): (`y`),
          {refinement = Maybe; writes = (2, 4) to (2, 5): (`y`)},
          {refinement = Not (Maybe); writes = (2, 4) to (2, 5): (`y`)}
        };
        (10, 0) to (10, 1) => {
          {refinement = Not (Not (Maybe)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "for_no_init_no_update_phi_refinement" =
  print_ssa_test {|let x = undefined;
for (; x != null; ) {
  if (x === 3) {
    break;
  }
  x;
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 7) to (2, 8) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 6) to (3, 7) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
        };
        (6, 2) to (6, 3) => {
          {refinement = Not (3); writes = {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}}
        };
        (8, 0) to (8, 1) => {
          (1, 4) to (1, 5): (`x`),
          {refinement = 3; writes = {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}},
          {refinement = Not (3); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "for_shadow" =
  print_ssa_test {|let x = undefined;
for (let x = null; x != null; x++) {
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 19) to (2, 20) => {
          (2, 9) to (2, 10): (`x`)
        };
        (2, 30) to (2, 31) => {
          {refinement = Not (Maybe); writes = (2, 9) to (2, 10): (`x`)}
        };
        (4, 0) to (4, 1) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "for" =
  print_ssa_test {|for (let x = 3; x != null; x++) {
  x;
}|};
    [%expect {|
      [
        (1, 16) to (1, 17) => {
          (1, 9) to (1, 10): (`x`)
        };
        (1, 27) to (1, 28) => {
          {refinement = Not (Maybe); writes = (1, 9) to (1, 10): (`x`)}
        };
        (2, 2) to (2, 3) => {
          {refinement = Not (Maybe); writes = (1, 9) to (1, 10): (`x`)}
        }] |}]

let%expect_test "for_throw" =
  print_ssa_test {|for (let x = 3; x != null; x++) {
  throw 'error';
}|};
    [%expect {|
      [
        (1, 16) to (1, 17) => {
          (1, 9) to (1, 10): (`x`)
        };
        (1, 27) to (1, 28) => {
          unreachable
        }] |}]

let%expect_test "for_break_with_control_flow_writes" =
  print_ssa_test {|let y = undefined;
for (let x = 3; x != null; x++) {
  if (y == null) {
    break;
  }
  y;
}
y;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 16) to (2, 17) => {
          (2, 9) to (2, 10): (`x`)
        };
        (2, 27) to (2, 28) => {
          {refinement = Not (Maybe); writes = (2, 9) to (2, 10): (`x`)}
        };
        (3, 6) to (3, 7) => {
          (1, 4) to (1, 5): (`y`)
        };
        (6, 2) to (6, 3) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`y`)}
        };
        (8, 0) to (8, 1) => {
          (1, 4) to (1, 5): (`y`),
          {refinement = Maybe; writes = (1, 4) to (1, 5): (`y`)},
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`y`)}
        }] |}]

let%expect_test "for_with_runtime_writes" =
  print_ssa_test {|let y = undefined;
for (let x = 3; x != null; x++) {
  if (y == null) {
    x = 2;
  }
  y;
}
y;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 16) to (2, 17) => {
          (2, 9) to (2, 10): (`x`)
        };
        (2, 27) to (2, 28) => {
          (4, 4) to (4, 5): (`x`),
          {refinement = Not (Maybe); writes = (2, 9) to (2, 10): (`x`)}
        };
        (3, 6) to (3, 7) => {
          (1, 4) to (1, 5): (`y`)
        };
        (6, 2) to (6, 3) => {
          (1, 4) to (1, 5): (`y`)
        };
        (8, 0) to (8, 1) => {
          (1, 4) to (1, 5): (`y`)
        }] |}]

let%expect_test "for_continue" =
  print_ssa_test {|for (let x = 3; x != null; x++) {
  continue;
}
x;|};
    [%expect {|
      [
        (1, 16) to (1, 17) => {
          (1, 9) to (1, 10): (`x`)
        };
        (1, 27) to (1, 28) => {
          {refinement = Not (Maybe); writes = (1, 9) to (1, 10): (`x`)}
        };
        (4, 0) to (4, 1) => {
          Global x
        }] |}]

let%expect_test "for_continue_with_control_flow_writes" =
  print_ssa_test {|let y = undefined;
for (let x = 3; x != null; x++) {
  if (y == null) {
    continue;
  }
  y;
}
y;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 16) to (2, 17) => {
          (2, 9) to (2, 10): (`x`)
        };
        (2, 27) to (2, 28) => {
          {refinement = Not (Maybe); writes = (2, 9) to (2, 10): (`x`)}
        };
        (3, 6) to (3, 7) => {
          (1, 4) to (1, 5): (`y`)
        };
        (6, 2) to (6, 3) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`y`)}
        };
        (8, 0) to (8, 1) => {
          (1, 4) to (1, 5): (`y`),
          {refinement = Maybe; writes = (1, 4) to (1, 5): (`y`)},
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`y`)}
        }] |}]

let%expect_test "no_havoc_before_write_seen" =
  print_ssa_test {|function f() { return 42 }
var x: number;
x;
x = 42;|};
  [%expect {|
    [
      (3, 0) to (3, 1) => {
        (uninitialized)
      }] |}]

let%expect_test "havoc_before_write_seen" =
  print_ssa_test {|function f() { return 42 }
f();
var x: number;
x;
x = 42;|};
  [%expect {|
    [
      (2, 0) to (2, 1) => {
        (1, 9) to (1, 10): (`f`)
      };
      (4, 0) to (4, 1) => {
        (uninitialized)
      }] |}]

let%expect_test "dont_havoc_to_uninit_in_function" =
  print_ssa_test {|function f() { return 42 }
function g() { return f() }|};
  [%expect {|
    [
      (2, 22) to (2, 23) => {
        (1, 9) to (1, 10): (`f`)
      }] |}]

let%expect_test "declare_predicate_fn" =
  print_ssa_test {|declare function f(x: number): boolean %checks(x) |};
  [%expect {|
    [
      (1, 47) to (1, 48) => {
        (1, 19) to (1, 20): (`x`)
      }] |}]

let%expect_test "switch_decl" =
  print_ssa_test {|switch ('') { case '': const foo = ''; foo; };|};
  [%expect {|
    [
      (1, 39) to (1, 42) => {
        (1, 29) to (1, 32): (`foo`)
      }] |}]

let%expect_test "switch_weird_decl" =
  print_ssa_test {|switch ('') { case l: 0; break; case '': let l };|};
  [%expect {|
    [
      (1, 19) to (1, 20) => {
        (uninitialized)
      }] |}]

let%expect_test "for_in" =
  print_ssa_test {|let stuff = {}
for (let thing in stuff) {
  thing
}|};
    [%expect {|
      [
        (2, 18) to (2, 23) => {
          (1, 4) to (1, 9): (`stuff`)
        };
        (3, 2) to (3, 7) => {
          (2, 9) to (2, 14): (`thing`)
        }] |}]

let%expect_test "for_in_reassign" =
  print_ssa_test {|let stuff = {}
for (let thing in stuff) {
  thing;
  thing = 3;
}|};
    [%expect {|
      [
        (2, 18) to (2, 23) => {
          (1, 4) to (1, 9): (`stuff`)
        };
        (3, 2) to (3, 7) => {
          (2, 9) to (2, 14): (`thing`)
        }] |}]

let%expect_test "for_in_destructure" =
  print_ssa_test {|let stuff = {}
for (let {thing} in stuff) {
  thing;
}|};
    [%expect {|
      [
        (2, 20) to (2, 25) => {
          (1, 4) to (1, 9): (`stuff`)
        };
        (3, 2) to (3, 7) => {
          (2, 10) to (2, 15): (`thing`)
        }] |}]

let%expect_test "for_in_destructure_reassign" =
  print_ssa_test {|let stuff = {}
for (let {thing} in stuff) {
  thing;
  thing = 3;
}|};
    [%expect {|
      [
        (2, 20) to (2, 25) => {
          (1, 4) to (1, 9): (`stuff`)
        };
        (3, 2) to (3, 7) => {
          (2, 10) to (2, 15): (`thing`)
        }] |}]

let%expect_test "for_in_shadow" =
  print_ssa_test {|let thing = undefined;
let stuff = {}
for (let thing in stuff) {
  thing;
}
thing;|};
    [%expect {|
      [
        (1, 12) to (1, 21) => {
          Global undefined
        };
        (3, 18) to (3, 23) => {
          (2, 4) to (2, 9): (`stuff`)
        };
        (4, 2) to (4, 7) => {
          (3, 9) to (3, 14): (`thing`)
        };
        (6, 0) to (6, 5) => {
          (1, 4) to (1, 9): (`thing`)
        }] |}]

let%expect_test "for_in_throw" =
  print_ssa_test {|let x = undefined;
for (let thing in {}) {
  throw 'error';
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (5, 0) to (5, 1) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "for_in_break_with_control_flow_writes" =
  print_ssa_test {|let y = undefined;
for (let thing in {}) {
  if (y == null) {
    break;
  }
  y;
}
y;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (3, 6) to (3, 7) => {
          (1, 4) to (1, 5): (`y`)
        };
        (6, 2) to (6, 3) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`y`)}
        };
        (8, 0) to (8, 1) => {
          (1, 4) to (1, 5): (`y`),
          {refinement = Maybe; writes = (1, 4) to (1, 5): (`y`)},
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`y`)}
        }] |}]

let%expect_test "for_in_with_runtime_writes" =
  print_ssa_test {|let x = undefined;
let y = undefined;
for (let thing in {}) {
  if (y == null) {
    x = 2;
  }
  y;
}
y;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 17) => {
          Global undefined
        };
        (4, 6) to (4, 7) => {
          (2, 4) to (2, 5): (`y`)
        };
        (7, 2) to (7, 3) => {
          (2, 4) to (2, 5): (`y`)
        };
        (9, 0) to (9, 1) => {
          (2, 4) to (2, 5): (`y`)
        };
        (10, 0) to (10, 1) => {
          (1, 4) to (1, 5): (`x`),
          (5, 4) to (5, 5): (`x`)
        }] |}]

let%expect_test "for_in_continue" =
  print_ssa_test {|let x = undefined;
for (let thing in {}) {
  continue;
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (5, 0) to (5, 1) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "for_in_continue_with_control_flow_writes" =
  print_ssa_test {|let y = undefined;
for (let thing in {}) {
  if (y == null) {
    continue;
  }
  y;
}
y;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (3, 6) to (3, 7) => {
          (1, 4) to (1, 5): (`y`)
        };
        (6, 2) to (6, 3) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`y`)}
        };
        (8, 0) to (8, 1) => {
          (1, 4) to (1, 5): (`y`),
          {refinement = Maybe; writes = (1, 4) to (1, 5): (`y`)},
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`y`)}
        }] |}]

let%expect_test "for_in_reassign_right" =
  print_ssa_test {|let stuff = {};
for (let thing in stuff) {
  stuff = [];
}
stuff;|};
    [%expect {|
      [
        (2, 18) to (2, 23) => {
          (1, 4) to (1, 9): (`stuff`)
        };
        (5, 0) to (5, 5) => {
          (1, 4) to (1, 9): (`stuff`),
          (3, 2) to (3, 7): (`stuff`)
        }] |}]

let%expect_test "for_of" =
  print_ssa_test {|let stuff = {}
for (let thing of stuff) {
  thing
}|};
    [%expect {|
      [
        (2, 18) to (2, 23) => {
          (1, 4) to (1, 9): (`stuff`)
        };
        (3, 2) to (3, 7) => {
          (2, 9) to (2, 14): (`thing`)
        }] |}]

let%expect_test "for_of_reassign" =
  print_ssa_test {|let stuff = {}
for (let thing of stuff) {
  thing;
  thing = 3;
}|};
    [%expect {|
      [
        (2, 18) to (2, 23) => {
          (1, 4) to (1, 9): (`stuff`)
        };
        (3, 2) to (3, 7) => {
          (2, 9) to (2, 14): (`thing`)
        }] |}]

let%expect_test "for_of_destructure" =
  print_ssa_test {|let stuff = {}
for (let {thing} of stuff) {
  thing;
}|};
    [%expect {|
      [
        (2, 20) to (2, 25) => {
          (1, 4) to (1, 9): (`stuff`)
        };
        (3, 2) to (3, 7) => {
          (2, 10) to (2, 15): (`thing`)
        }] |}]

let%expect_test "for_of_destructure_reassign" =
  print_ssa_test {|let stuff = {}
for (let {thing} of stuff) {
  thing;
  thing = 3;
}|};
    [%expect {|
      [
        (2, 20) to (2, 25) => {
          (1, 4) to (1, 9): (`stuff`)
        };
        (3, 2) to (3, 7) => {
          (2, 10) to (2, 15): (`thing`)
        }] |}]

let%expect_test "for_of_shadow" =
  print_ssa_test {|let thing = undefined;
let stuff = {}
for (let thing of stuff) {
  thing;
}
thing;|};
    [%expect {|
      [
        (1, 12) to (1, 21) => {
          Global undefined
        };
        (3, 18) to (3, 23) => {
          (2, 4) to (2, 9): (`stuff`)
        };
        (4, 2) to (4, 7) => {
          (3, 9) to (3, 14): (`thing`)
        };
        (6, 0) to (6, 5) => {
          (1, 4) to (1, 9): (`thing`)
        }] |}]

let%expect_test "for_of_throw" =
  print_ssa_test {|let x = undefined;
for (let thing of {}) {
  throw 'error';
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (5, 0) to (5, 1) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "for_of_break_with_control_flow_writes" =
  print_ssa_test {|let y = undefined;
for (let thing of {}) {
  if (y == null) {
    break;
  }
  y;
}
y;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (3, 6) to (3, 7) => {
          (1, 4) to (1, 5): (`y`)
        };
        (6, 2) to (6, 3) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`y`)}
        };
        (8, 0) to (8, 1) => {
          (1, 4) to (1, 5): (`y`),
          {refinement = Maybe; writes = (1, 4) to (1, 5): (`y`)},
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`y`)}
        }] |}]

let%expect_test "for_of_with_runtime_writes" =
  print_ssa_test {|let x = undefined;
let y = undefined;
for (let thing of {}) {
  if (y == null) {
    x = 2;
  }
  y;
}
y;
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 17) => {
          Global undefined
        };
        (4, 6) to (4, 7) => {
          (2, 4) to (2, 5): (`y`)
        };
        (7, 2) to (7, 3) => {
          (2, 4) to (2, 5): (`y`)
        };
        (9, 0) to (9, 1) => {
          (2, 4) to (2, 5): (`y`)
        };
        (10, 0) to (10, 1) => {
          (1, 4) to (1, 5): (`x`),
          (5, 4) to (5, 5): (`x`)
        }] |}]

let%expect_test "for_of_continue" =
  print_ssa_test {|let x = undefined;
for (let thing of {}) {
  continue;
}
x;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (5, 0) to (5, 1) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "for_of_continue_with_control_flow_writes" =
  print_ssa_test {|let y = undefined;
for (let thing of {}) {
  if (y == null) {
    continue;
  }
  y;
}
y;|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (3, 6) to (3, 7) => {
          (1, 4) to (1, 5): (`y`)
        };
        (6, 2) to (6, 3) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`y`)}
        };
        (8, 0) to (8, 1) => {
          (1, 4) to (1, 5): (`y`),
          {refinement = Maybe; writes = (1, 4) to (1, 5): (`y`)},
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`y`)}
        }] |}]

let%expect_test "for_of_reassign_right" =
  print_ssa_test {|let stuff = {};
for (let thing of stuff) {
  stuff = [];
}
stuff;|};
    [%expect {|
      [
        (2, 18) to (2, 23) => {
          (1, 4) to (1, 9): (`stuff`)
        };
        (5, 0) to (5, 5) => {
          (1, 4) to (1, 9): (`stuff`),
          (3, 2) to (3, 7): (`stuff`)
        }] |}]

let%expect_test "invariant" =
  print_ssa_test {|let x = undefined;
invariant(x != null, "other arg");
x;
|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 0) to (2, 9) => {
          Global invariant
        };
        (2, 10) to (2, 11) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 0) to (3, 1) => {
          {refinement = Not (Maybe); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "invariant_false" =
  print_ssa_test {|let x = undefined;
if (x === 3) {
  invariant(false);
}
x;
|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 4) to (2, 5) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 2) to (3, 11) => {
          Global invariant
        };
        (5, 0) to (5, 1) => {
          {refinement = Not (3); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "invariant_no_args" =
  print_ssa_test {|let x = undefined;
if (x === 3) {
  invariant();
}
x;
|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 4) to (2, 5) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 2) to (3, 11) => {
          Global invariant
        };
        (5, 0) to (5, 1) => {
          {refinement = Not (3); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "invariant_reassign" =
  print_ssa_test {|let x = undefined;
if (true) {
  invariant(false, x = 3);
}
x;
|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (3, 2) to (3, 11) => {
          Global invariant
        };
        (5, 0) to (5, 1) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "try_catch_invariant_reassign" =
  print_ssa_test {|let x = undefined;

try {
  if (true) {
    invariant(false, x = 3);
  }
} finally {
  x;
}|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (5, 4) to (5, 13) => {
          Global invariant
        };
        (8, 2) to (8, 3) => {
          (1, 4) to (1, 5): (`x`),
          (5, 21) to (5, 22): (`x`)
        }] |}]

let%expect_test "switch_empty" =
  print_ssa_test {|let x = undefined;
switch (x) {};
x;
|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 9) => {
          (1, 4) to (1, 5): (`x`)
        };
        (3, 0) to (3, 1) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "switch_only_default" =
  print_ssa_test {|let x = undefined;
switch (x) {
  default: {
    x;
  }
};
x;
|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 9) => {
          (1, 4) to (1, 5): (`x`)
        };
        (4, 4) to (4, 5) => {
          (1, 4) to (1, 5): (`x`)
        };
        (7, 0) to (7, 1) => {
          (1, 4) to (1, 5): (`x`)
        }] |}]

let%expect_test "switch_break_every_case" =
  print_ssa_test {|let x = undefined;
switch (x) {
  case null:
    x;
    break;
  case 3:
    x;
    break;
  case false:
    x;
    break;
  default: {
    x;
  }
};
x;
|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 9) => {
          (1, 4) to (1, 5): (`x`)
        };
        (4, 4) to (4, 5) => {
          {refinement = Null; writes = (1, 4) to (1, 5): (`x`)}
        };
        (7, 4) to (7, 5) => {
          {refinement = 3; writes = (1, 4) to (1, 5): (`x`)}
        };
        (10, 4) to (10, 5) => {
          {refinement = false; writes = (1, 4) to (1, 5): (`x`)}
        };
        (13, 4) to (13, 5) => {
          {refinement = And (And (Not (false), Not (3)), Not (Null)); writes = (1, 4) to (1, 5): (`x`)}
        };
        (16, 0) to (16, 1) => {
          {refinement = Null; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = 3; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = false; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = And (And (Not (false), Not (3)), Not (Null)); writes = (1, 4) to (1, 5): (`x`)}
        }]|}]

let%expect_test "switch_with_fallthroughs" =
  print_ssa_test {|let x = undefined;
switch (x) {
  case null:
    x;
  case 3:
    x;
    break;
  case true:
  case false:
    x;
  default: {
    x;
  }
};
x;
|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 9) => {
          (1, 4) to (1, 5): (`x`)
        };
        (4, 4) to (4, 5) => {
          {refinement = Null; writes = (1, 4) to (1, 5): (`x`)}
        };
        (6, 4) to (6, 5) => {
          {refinement = Null; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = 3; writes = (1, 4) to (1, 5): (`x`)}
        };
        (10, 4) to (10, 5) => {
          {refinement = true; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = false; writes = (1, 4) to (1, 5): (`x`)}
        };
        (12, 4) to (12, 5) => {
          {refinement = true; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = false; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = And (And (And (Not (false), Not (true)), Not (3)), Not (Null)); writes = (1, 4) to (1, 5): (`x`)}
        };
        (15, 0) to (15, 1) => {
          {refinement = Null; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = 3; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = true; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = false; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = And (And (And (Not (false), Not (true)), Not (3)), Not (Null)); writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "switch_throw_in_default" =
  print_ssa_test {|let x = undefined;
switch (x) {
  case null:
    x;
  case 3:
    x;
    break;
  case true:
  case false:
    x;
    break;
  default: {
    throw 'error'
  }
};
x;
|};
    [%expect {|
      [
        (1, 8) to (1, 17) => {
          Global undefined
        };
        (2, 8) to (2, 9) => {
          (1, 4) to (1, 5): (`x`)
        };
        (4, 4) to (4, 5) => {
          {refinement = Null; writes = (1, 4) to (1, 5): (`x`)}
        };
        (6, 4) to (6, 5) => {
          {refinement = Null; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = 3; writes = (1, 4) to (1, 5): (`x`)}
        };
        (10, 4) to (10, 5) => {
          {refinement = true; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = false; writes = (1, 4) to (1, 5): (`x`)}
        };
        (16, 0) to (16, 1) => {
          {refinement = Null; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = 3; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = true; writes = (1, 4) to (1, 5): (`x`)},
          {refinement = false; writes = (1, 4) to (1, 5): (`x`)}
        }] |}]

let%expect_test "global_refinement" =
  print_ssa_test {|
Map != null && Map
|};
    [%expect {|
      [
        (2, 0) to (2, 3) => {
          Global Map
        };
        (2, 15) to (2, 18) => {
          {refinement = Not (Maybe); writes = Global Map}
        }] |}]

let%expect_test "global_refinement_control_flow" =
  print_ssa_test {|
if (Map != null) {
  throw 'error';
}
Map;
|};
    [%expect {|
      [
        (2, 4) to (2, 7) => {
          Global Map
        };
        (5, 0) to (5, 3) => {
          {refinement = Not (Not (Maybe)); writes = Global Map}
        }] |}]

let%expect_test "global_overwrite" =
  print_ssa_test {|
if (true) {
  undefined = null;
}
undefined;
|};
    [%expect {|
      [
        (5, 0) to (5, 9) => {
          Global undefined,
          (3, 2) to (3, 11): (`undefined`)
        }] |}]

let%expect_test "havoc_from_uninitialized" =
  print_ssa_test {|
var x: number;
function havoc() {
    x = 42;
}
havoc();
(x: void)
// todo: this should probably also include undefined
|};
  [%expect {|
    [
      (6, 0) to (6, 5) => {
        (3, 9) to (3, 14): (`havoc`)
      };
      (7, 1) to (7, 2) => {
        (uninitialized),
        (2, 4) to (2, 5): (`x`)
      }] |}]

let%expect_test "captured_havoc" =
  print_ssa_test {|function g() {
  var xx : { p : number } | null = { p : 4 };
  if (xx) {
    return function () {
       xx.p = 3;
    }
  }
}
|};
  [%expect {|
    [
      (3, 6) to (3, 8) => {
        (2, 6) to (2, 8): (`xx`)
      };
      (5, 7) to (5, 9) => {
        {refinement = Truthy; writes = (2, 6) to (2, 8): (`xx`)}
      }] |}]

let%expect_test "no_providers" =
  print_ssa_test {|
var x;
function fn() {
    x;
}
|};
  [%expect {|
    [
      (4, 4) to (4, 5) => {
        (uninitialized)
      }] |}]

let%expect_test "class_expr" =
  print_ssa_test {|
let y = 42;
let x = class y { m() { x; y } };
y;
|};
    [%expect {|
      [
        (3, 24) to (3, 25) => {
          (3, 4) to (3, 5): (`x`)
        };
        (3, 27) to (3, 28) => {
          (3, 14) to (3, 15): (`y`)
        };
        (4, 0) to (4, 1) => {
          (2, 4) to (2, 5): (`y`)
        }]|}]

let%expect_test "havoc" =
  print_ssa_test {|
let x = 3;
function f() { x = 'string'}
let y = 3;
if (x != null && y != null) {
  f();
  x;
  y;
}
|};
    [%expect {|
      [
        (5, 4) to (5, 5) => {
          (2, 4) to (2, 5): (`x`)
        };
        (5, 17) to (5, 18) => {
          (4, 4) to (4, 5): (`y`)
        };
        (6, 2) to (6, 3) => {
          (3, 9) to (3, 10): (`f`)
        };
        (7, 2) to (7, 3) => {
          (2, 4) to (2, 5): (`x`)
        };
        (8, 2) to (8, 3) => {
          {refinement = Not (Maybe); writes = (4, 4) to (4, 5): (`y`)}
        }] |}]

let%expect_test "predicate_function_outside_predicate_position" =
  print_ssa_test {|
let x = null;
let y = 3;
function f(x): %checks { return x != null }
f(x, y);
x;
y;

x = 'string';
|};
    [%expect {|
      [
        (4, 32) to (4, 33) => {
          (4, 11) to (4, 12): (`x`)
        };
        (5, 0) to (5, 1) => {
          (4, 9) to (4, 10): (`f`)
        };
        (5, 2) to (5, 3) => {
          (2, 4) to (2, 5): (`x`)
        };
        (5, 5) to (5, 6) => {
          (3, 4) to (3, 5): (`y`)
        };
        (6, 0) to (6, 1) => {
          (2, 4) to (2, 5): (`x`)
        };
        (7, 0) to (7, 1) => {
          (3, 4) to (3, 5): (`y`)
        }] |}]

let%expect_test "latent_refinements" =
  print_ssa_test {|
let x = 3;
function f() { x = 'string'}
let y = 3;
if (f(x, y)) {
  x;
  y;
}
if (y.f(x, y)) {
  // No refinements on either
  x;
  y;
}
|};
    [%expect {|
      [
        (5, 4) to (5, 5) => {
          (3, 9) to (3, 10): (`f`)
        };
        (5, 6) to (5, 7) => {
          (2, 4) to (2, 5): (`x`)
        };
        (5, 9) to (5, 10) => {
          (4, 4) to (4, 5): (`y`)
        };
        (6, 2) to (6, 3) => {
          {refinement = LatentR (index = 0); writes = (2, 4) to (2, 5): (`x`)}
        };
        (7, 2) to (7, 3) => {
          {refinement = LatentR (index = 1); writes = (4, 4) to (4, 5): (`y`)}
        };
        (9, 4) to (9, 5) => {
          (4, 4) to (4, 5): (`y`)
        };
        (9, 8) to (9, 9) => {
          (2, 4) to (2, 5): (`x`)
        };
        (9, 11) to (9, 12) => {
          (4, 4) to (4, 5): (`y`)
        };
        (11, 2) to (11, 3) => {
          (2, 4) to (2, 5): (`x`)
        };
        (12, 2) to (12, 3) => {
          (4, 4) to (4, 5): (`y`)
        }] |}]

let%expect_test "heap_refinement_basic" =
  print_ssa_test {|
let x = {};
if (x.foo === 3) {
  x.foo;
  if (x.foo === 4) {
    x.foo;
  }
}
|};
    [%expect {|
      [
        (3, 4) to (3, 5) => {
          (2, 4) to (2, 5): (`x`)
        };
        (4, 2) to (4, 3) => {
          {refinement = SentinelR foo; writes = (2, 4) to (2, 5): (`x`)}
        };
        (4, 2) to (4, 7) => {
          {refinement = 3; writes = projection}
        };
        (5, 6) to (5, 7) => {
          {refinement = SentinelR foo; writes = (2, 4) to (2, 5): (`x`)}
        };
        (5, 6) to (5, 11) => {
          {refinement = 3; writes = projection}
        };
        (6, 4) to (6, 5) => {
          {refinement = SentinelR foo; writes = {refinement = SentinelR foo; writes = (2, 4) to (2, 5): (`x`)}}
        };
        (6, 4) to (6, 9) => {
          {refinement = 4; writes = {refinement = 3; writes = projection}}
        }] |}]

let%expect_test "heap_refinement_basic" =
  print_ssa_test {|
let x = {};
if (x.foo === 3) {
  x.foo;
  if (x.foo === 4) {
    x.foo;
  }
}
|};
    [%expect {|
      [
        (3, 4) to (3, 5) => {
          (2, 4) to (2, 5): (`x`)
        };
        (4, 2) to (4, 3) => {
          {refinement = SentinelR foo; writes = (2, 4) to (2, 5): (`x`)}
        };
        (4, 2) to (4, 7) => {
          {refinement = 3; writes = projection}
        };
        (5, 6) to (5, 7) => {
          {refinement = SentinelR foo; writes = (2, 4) to (2, 5): (`x`)}
        };
        (5, 6) to (5, 11) => {
          {refinement = 3; writes = projection}
        };
        (6, 4) to (6, 5) => {
          {refinement = SentinelR foo; writes = {refinement = SentinelR foo; writes = (2, 4) to (2, 5): (`x`)}}
        };
        (6, 4) to (6, 9) => {
          {refinement = 4; writes = {refinement = 3; writes = projection}}
        }] |}]

let%expect_test "heap_refinement_merge_branches" =
  print_ssa_test {|
declare var invariant: any;
let x = {};
if (true) {
  invariant(x.foo === 3);
} else {
  invariant(x.foo === 4);
}
x.foo; // 3 | 4
|};
    [%expect {|
      [
        (5, 2) to (5, 11) => {
          (2, 12) to (2, 21): (`invariant`)
        };
        (5, 12) to (5, 13) => {
          (3, 4) to (3, 5): (`x`)
        };
        (7, 2) to (7, 11) => {
          (2, 12) to (2, 21): (`invariant`)
        };
        (7, 12) to (7, 13) => {
          (3, 4) to (3, 5): (`x`)
        };
        (9, 0) to (9, 1) => {
          {refinement = SentinelR foo; writes = (3, 4) to (3, 5): (`x`)},
          {refinement = SentinelR foo; writes = (3, 4) to (3, 5): (`x`)}
        };
        (9, 0) to (9, 5) => {
          {refinement = 3; writes = projection},
          {refinement = 4; writes = projection}
        }] |}]

let%expect_test "heap_refinement_one_branch" =
  print_ssa_test {|
declare var invariant: any;
let x = {};
if (true) {
  invariant(x.foo === 3);
} else {
}
x.foo; // No refinement
|};
    [%expect {|
      [
        (5, 2) to (5, 11) => {
          (2, 12) to (2, 21): (`invariant`)
        };
        (5, 12) to (5, 13) => {
          (3, 4) to (3, 5): (`x`)
        };
        (8, 0) to (8, 1) => {
          (3, 4) to (3, 5): (`x`),
          {refinement = SentinelR foo; writes = (3, 4) to (3, 5): (`x`)}
        }] |}]

let%expect_test "heap_refinement_while_loop_subject_changed" =
  print_ssa_test {|
let x = {};
while (x.foo === 3) {
  x.foo;
  x = {};
  break;
}
x.foo; // No heap refinement here
|};
    [%expect {|
      [
        (3, 7) to (3, 8) => {
          (2, 4) to (2, 5): (`x`)
        };
        (4, 2) to (4, 3) => {
          {refinement = SentinelR foo; writes = (2, 4) to (2, 5): (`x`)}
        };
        (4, 2) to (4, 7) => {
          {refinement = 3; writes = projection}
        };
        (8, 0) to (8, 1) => {
          (2, 4) to (2, 5): (`x`),
          (5, 2) to (5, 3): (`x`)
        }] |}]

let%expect_test "heap_refinement_while_loop_projection_changed" =
  print_ssa_test {|
declare var invariant: any;
let x = {};
while (x.foo === 3) {
  invariant(x.foo === 4);
  x.foo;
  break;
}
x.foo; // No heap refinement here
|};
    [%expect {|
      [
        (4, 7) to (4, 8) => {
          (3, 4) to (3, 5): (`x`)
        };
        (5, 2) to (5, 11) => {
          (2, 12) to (2, 21): (`invariant`)
        };
        (5, 12) to (5, 13) => {
          {refinement = SentinelR foo; writes = (3, 4) to (3, 5): (`x`)}
        };
        (5, 12) to (5, 17) => {
          {refinement = 3; writes = projection}
        };
        (6, 2) to (6, 3) => {
          {refinement = SentinelR foo; writes = {refinement = SentinelR foo; writes = (3, 4) to (3, 5): (`x`)}}
        };
        (6, 2) to (6, 7) => {
          {refinement = 4; writes = {refinement = 3; writes = projection}}
        };
        (9, 0) to (9, 1) => {
          (3, 4) to (3, 5): (`x`),
          {refinement = SentinelR foo; writes = {refinement = SentinelR foo; writes = (3, 4) to (3, 5): (`x`)}}
        }] |}]

let%expect_test "heap_refinement_while_loop_negated" =
  print_ssa_test {|
let x = {};
while (x.foo === 3) {
  x.foo;
}
x.foo;
|};
    [%expect {|
      [
        (3, 7) to (3, 8) => {
          (2, 4) to (2, 5): (`x`)
        };
        (4, 2) to (4, 3) => {
          {refinement = SentinelR foo; writes = (2, 4) to (2, 5): (`x`)}
        };
        (4, 2) to (4, 7) => {
          {refinement = 3; writes = projection}
        };
        (6, 0) to (6, 1) => {
          {refinement = Not (SentinelR foo); writes = (2, 4) to (2, 5): (`x`)}
        };
        (6, 0) to (6, 5) => {
          {refinement = Not (3); writes = projection}
        }] |}]

let%expect_test "heap_refinement_loop_control_flow_write" =
  print_ssa_test {|
let x = {};
while (x.foo === 3) {
  if (x.foo === 4) {
    x.foo;
  } else { throw 'error'}
  x.foo;
}
x.foo; // x.foo === 4 refinement should not be present
|};
    [%expect {|
      [
        (3, 7) to (3, 8) => {
          (2, 4) to (2, 5): (`x`)
        };
        (4, 6) to (4, 7) => {
          {refinement = SentinelR foo; writes = (2, 4) to (2, 5): (`x`)}
        };
        (4, 6) to (4, 11) => {
          {refinement = 3; writes = projection}
        };
        (5, 4) to (5, 5) => {
          {refinement = SentinelR foo; writes = {refinement = SentinelR foo; writes = (2, 4) to (2, 5): (`x`)}}
        };
        (5, 4) to (5, 9) => {
          {refinement = 4; writes = {refinement = 3; writes = projection}}
        };
        (7, 2) to (7, 3) => {
          {refinement = SentinelR foo; writes = {refinement = SentinelR foo; writes = (2, 4) to (2, 5): (`x`)}}
        };
        (9, 0) to (9, 1) => {
          {refinement = Not (SentinelR foo); writes = (2, 4) to (2, 5): (`x`),{refinement = SentinelR foo; writes = (2, 4) to (2, 5): (`x`)}}
        };
        (9, 0) to (9, 5) => {
          {refinement = Not (3); writes = projection}
        }] |}]

let%expect_test "heap_refinement_write" =
  print_ssa_test {|
let x = {};
x.foo = 3;
x.foo;
|};
    [%expect {|
      [
        (3, 0) to (3, 1) => {
          (2, 4) to (2, 5): (`x`)
        };
        (4, 0) to (4, 1) => {
          (2, 4) to (2, 5): (`x`)
        };
        (4, 0) to (4, 5) => {
          (3, 0) to (3, 5): (some property)
        }] |}]

let%expect_test "heap_refinement_write_havoc_member" =
  print_ssa_test {|
let x = {};
x.foo = 3;
let y = x;
y.foo = 3;
x.foo; // should no longer be refined
y.foo; // still refined
|};
    [%expect {|
      [
        (3, 0) to (3, 1) => {
          (2, 4) to (2, 5): (`x`)
        };
        (4, 8) to (4, 9) => {
          (2, 4) to (2, 5): (`x`)
        };
        (5, 0) to (5, 1) => {
          (4, 4) to (4, 5): (`y`)
        };
        (6, 0) to (6, 1) => {
          (2, 4) to (2, 5): (`x`)
        };
        (7, 0) to (7, 1) => {
          (4, 4) to (4, 5): (`y`)
        };
        (7, 0) to (7, 5) => {
          (5, 0) to (5, 5): (some property)
        }] |}]

let%expect_test "heap_refinement_write_havoc_elem" =
  print_ssa_test {|
let x = {};
x.foo = 3;
let y = x;
y.foo = 3;
y[x] = 4;
x.foo; // should no longer be refined
y.foo; // should no longer be refined
|};
    [%expect {|
      [
        (3, 0) to (3, 1) => {
          (2, 4) to (2, 5): (`x`)
        };
        (4, 8) to (4, 9) => {
          (2, 4) to (2, 5): (`x`)
        };
        (5, 0) to (5, 1) => {
          (4, 4) to (4, 5): (`y`)
        };
        (6, 0) to (6, 1) => {
          (4, 4) to (4, 5): (`y`)
        };
        (6, 2) to (6, 3) => {
          (2, 4) to (2, 5): (`x`)
        };
        (7, 0) to (7, 1) => {
          (2, 4) to (2, 5): (`x`)
        };
        (8, 0) to (8, 1) => {
          (4, 4) to (4, 5): (`y`)
        }] |}]

let%expect_test "heap_refinement_havoc_on_write" =
  print_ssa_test {|
let x = {};
x.foo = 3;
x.foo;
x = {};
x.foo; // No more refinement
|};
    [%expect {|
      [
        (3, 0) to (3, 1) => {
          (2, 4) to (2, 5): (`x`)
        };
        (4, 0) to (4, 1) => {
          (2, 4) to (2, 5): (`x`)
        };
        (4, 0) to (4, 5) => {
          (3, 0) to (3, 5): (some property)
        };
        (6, 0) to (6, 1) => {
          (5, 0) to (5, 1): (`x`)
        }] |}]

let%expect_test "unreachable_code" =
  print_ssa_test {|
x = 4;
x;
throw new Error();
var x = 3;
x;
|};
    [%expect {|
      [
        (3, 0) to (3, 1) => {
          (2, 0) to (2, 1): (`x`)
        };
        (4, 10) to (4, 15) => {
          Global Error
        };
        (6, 0) to (6, 1) => {
          unreachable
        }] |}]

let%expect_test "function_hoisted_typeof" =
  print_ssa_test {|
let x = null;
if (Math.random()) {
  x = 'string';
} else {
  x = 4;
}

x = 5;
// Note that the typeofs here report all the providers and not x = 5
function f<T: typeof x = typeof x>(y: typeof x): typeof x { return null; }
declare function f<T: typeof x = typeof x>(y: typeof x): typeof x;
// The return here should not be hoisted, but the param is because
// we havoc before we visit the params.
let y = (z: typeof x): typeof x => 3;
|};
    [%expect {|
      [
        (3, 4) to (3, 8) => {
          Global Math
        };
        (11, 21) to (11, 22) => {
          (2, 4) to (2, 5): (`x`),
          (4, 2) to (4, 3): (`x`),
          (6, 2) to (6, 3): (`x`)
        };
        (11, 32) to (11, 33) => {
          (2, 4) to (2, 5): (`x`),
          (4, 2) to (4, 3): (`x`),
          (6, 2) to (6, 3): (`x`)
        };
        (11, 45) to (11, 46) => {
          (2, 4) to (2, 5): (`x`),
          (4, 2) to (4, 3): (`x`),
          (6, 2) to (6, 3): (`x`)
        };
        (11, 56) to (11, 57) => {
          (2, 4) to (2, 5): (`x`),
          (4, 2) to (4, 3): (`x`),
          (6, 2) to (6, 3): (`x`)
        };
        (12, 29) to (12, 30) => {
          (2, 4) to (2, 5): (`x`),
          (4, 2) to (4, 3): (`x`),
          (6, 2) to (6, 3): (`x`)
        };
        (12, 40) to (12, 41) => {
          (2, 4) to (2, 5): (`x`),
          (4, 2) to (4, 3): (`x`),
          (6, 2) to (6, 3): (`x`)
        };
        (12, 43) to (12, 44) => {
          (15, 4) to (15, 5): (`y`)
        };
        (12, 53) to (12, 54) => {
          (2, 4) to (2, 5): (`x`),
          (4, 2) to (4, 3): (`x`),
          (6, 2) to (6, 3): (`x`)
        };
        (12, 64) to (12, 65) => {
          (2, 4) to (2, 5): (`x`),
          (4, 2) to (4, 3): (`x`),
          (6, 2) to (6, 3): (`x`)
        };
        (15, 19) to (15, 20) => {
          (2, 4) to (2, 5): (`x`),
          (4, 2) to (4, 3): (`x`),
          (6, 2) to (6, 3): (`x`)
        };
        (15, 30) to (15, 31) => {
          (9, 0) to (9, 1): (`x`)
        }] |}]

let%expect_test "hoisted_global_refinement" =
  print_ssa_test {|
if (global != null) {
  global;
  function f(x: typeof global) { }
}
|};
    [%expect {|
      [
        (2, 4) to (2, 10) => {
          Global global
        };
        (3, 2) to (3, 8) => {
          {refinement = Not (Maybe); writes = Global global}
        };
        (4, 23) to (4, 29) => {
          Global global
        }] |}]

let%expect_test "type_alias" =
  print_ssa_test {|
type t = number;
let x: t = 42;
|};
    [%expect {|
      [
        (3, 7) to (3, 8) => {
          (2, 5) to (2, 6): (`t`)
        }] |}]

let%expect_test "type_alias_global" =
  print_ssa_test {|
let x: t = 42;
|};
    [%expect {|
      [
        (2, 7) to (2, 8) => {
          Global t
        }] |}]

let%expect_test "type_alias_refine" =
  print_ssa_test {|
if (t) {
  let x: t = 42;
}
|};
    [%expect {|
      [
        (2, 4) to (2, 5) => {
          Global t
        };
        (3, 9) to (3, 10) => {
          {refinement = Truthy; writes = Global t}
        }] |}]

let%expect_test "type_alias_no_init" =
  print_ssa_test {|
type t = number;
let x: t;
|};
    [%expect {|
      [
        (3, 7) to (3, 8) => {
          (2, 5) to (2, 6): (`t`)
        }] |}]

let%expect_test "type_alias_lookup" =
  print_ssa_test {|
import * as React from 'react';
type T = React.ComponentType;
var C: React.ComponentType;
|};
    [%expect {|
      [
        (3, 9) to (3, 14) => {
          (2, 12) to (2, 17): (`React`)
        };
        (4, 7) to (4, 12) => {
          (2, 12) to (2, 17): (`React`)
        }] |}]

let%expect_test "class_as_type" =
  print_ssa_test {|
class C { }
var x: C = new C();
|};
    [%expect {|
      [
        (3, 7) to (3, 8) => {
          (2, 6) to (2, 7): (`C`)
        };
        (3, 15) to (3, 16) => {
          (2, 6) to (2, 7): (`C`)
        }] |}]

let%expect_test "interface_as_type" =
  print_ssa_test {|
interface C { }
var x: C;
|};
    [%expect {|
      [
        (3, 7) to (3, 8) => {
          (2, 10) to (2, 11): (`C`)
        }] |}]

let%expect_test "hoist_type" =
  print_ssa_test {|
var x: T;
type T = number;
|};
    [%expect {|
      [
        (2, 7) to (2, 8) => {
          (3, 5) to (3, 6): (`T`)
        }] |}]

let%expect_test "hoist_interface" =
  print_ssa_test {|
var x: C;
interface C { }
|};
    [%expect {|
      [
        (2, 7) to (2, 8) => {
          (3, 10) to (3, 11): (`C`)
        }] |}]

let%expect_test "opaque" =
  print_ssa_test {|
var x: T;
opaque type T: C = C;
interface C { }
|};
    [%expect {|
      [
        (2, 7) to (2, 8) => {
          (3, 12) to (3, 13): (`T`)
        };
        (3, 15) to (3, 16) => {
          (4, 10) to (4, 11): (`C`)
        };
        (3, 19) to (3, 20) => {
          (4, 10) to (4, 11): (`C`)
        }] |}]

let%expect_test "mutual" =
  print_ssa_test {|
type A = Array<B>;
type B = { a: A };
|};
    [%expect {|
      [
        (2, 9) to (2, 14) => {
          Global Array
        };
        (2, 15) to (2, 16) => {
          (3, 5) to (3, 6): (`B`)
        };
        (3, 14) to (3, 15) => {
          (2, 5) to (2, 6): (`A`)
        }] |}]

let%expect_test "fun_tparam" =
  print_ssa_test {|
function f<X, Y: X = number>(x: X, y: Y) {
  (x: Y);
}
|};
    [%expect {|
      [
        (2, 17) to (2, 18) => {
          (2, 11) to (2, 12): (`X`)
        };
        (2, 32) to (2, 33) => {
          (2, 11) to (2, 12): (`X`)
        };
        (2, 38) to (2, 39) => {
          (2, 14) to (2, 15): (`Y`)
        };
        (3, 3) to (3, 4) => {
          (2, 29) to (2, 30): (`x`)
        };
        (3, 6) to (3, 7) => {
          (2, 14) to (2, 15): (`Y`)
        }] |}]

let%expect_test "fun_tparam_return" =
  print_ssa_test {|
function f<X, Y: X = number>(x: X, y: Y): Y {
  (x: Y);
}
|};
    [%expect {|
      [
        (2, 17) to (2, 18) => {
          (2, 11) to (2, 12): (`X`)
        };
        (2, 32) to (2, 33) => {
          (2, 11) to (2, 12): (`X`)
        };
        (2, 38) to (2, 39) => {
          (2, 14) to (2, 15): (`Y`)
        };
        (2, 42) to (2, 43) => {
          (2, 14) to (2, 15): (`Y`)
        };
        (3, 3) to (3, 4) => {
          (2, 29) to (2, 30): (`x`)
        };
        (3, 6) to (3, 7) => {
          (2, 14) to (2, 15): (`Y`)
        }] |}]

let%expect_test "fun_tparam_global_bound" =
  print_ssa_test {|
function f<Z: Z>() { }
|};
    [%expect {|
      [
        (2, 14) to (2, 15) => {
          Global Z
        }] |}]

let%expect_test "fun_inline_tparam" =
  print_ssa_test {|
let x = function f<X, Y: X = number>(x: X, y: Y) {
  (x: Y);
}
|};
    [%expect {|
      [
        (2, 25) to (2, 26) => {
          (2, 19) to (2, 20): (`X`)
        };
        (2, 40) to (2, 41) => {
          (2, 19) to (2, 20): (`X`)
        };
        (2, 46) to (2, 47) => {
          (2, 22) to (2, 23): (`Y`)
        };
        (3, 3) to (3, 4) => {
          (2, 37) to (2, 38): (`x`)
        };
        (3, 6) to (3, 7) => {
          (2, 22) to (2, 23): (`Y`)
        }] |}]

let%expect_test "arrow_fun_tparam" =
  print_ssa_test {|
let x = <X, Y: X = number>(x: X, y: Y) => {
  (x: Y);
}
|};
    [%expect {|
      [
        (2, 15) to (2, 16) => {
          (2, 9) to (2, 10): (`X`)
        };
        (2, 30) to (2, 31) => {
          (2, 9) to (2, 10): (`X`)
        };
        (2, 36) to (2, 37) => {
          (2, 12) to (2, 13): (`Y`)
        };
        (3, 3) to (3, 4) => {
          (2, 27) to (2, 28): (`x`)
        };
        (3, 6) to (3, 7) => {
          (2, 12) to (2, 13): (`Y`)
        }] |}]

let%expect_test "type_tparam" =
  print_ssa_test {|
type T<X, Y: X = number> = Array<[X, Y]>
|};
    [%expect {|
      [
        (2, 13) to (2, 14) => {
          (2, 7) to (2, 8): (`X`)
        };
        (2, 27) to (2, 32) => {
          Global Array
        };
        (2, 34) to (2, 35) => {
          (2, 7) to (2, 8): (`X`)
        };
        (2, 37) to (2, 38) => {
          (2, 10) to (2, 11): (`Y`)
        }] |}]

let%expect_test "opaque_tparam" =
  print_ssa_test {|
opaque type T<X>: X = X
|};
    [%expect {|
      [
        (2, 18) to (2, 19) => {
          (2, 14) to (2, 15): (`X`)
        };
        (2, 22) to (2, 23) => {
          (2, 14) to (2, 15): (`X`)
        }] |}]

let%expect_test "opaque_tparam" =
  print_ssa_test {|
declare opaque type T<X>: X;
|};
    [%expect {|
      [
        (2, 26) to (2, 27) => {
          (2, 22) to (2, 23): (`X`)
        }] |}]

let%expect_test "interface_tparam" =
  print_ssa_test {|
interface T<X, Y:X> {
  x: X;
  y: Y;
};
|};
    [%expect {|
      [
        (2, 17) to (2, 18) => {
          (2, 12) to (2, 13): (`X`)
        };
        (3, 5) to (3, 6) => {
          (2, 12) to (2, 13): (`X`)
        };
        (4, 5) to (4, 6) => {
          (2, 15) to (2, 16): (`Y`)
        }] |}]

let%expect_test "interface_miss" =
  print_ssa_test {|
interface T<X> extends X { };
|};
    [%expect {|
      [
        (2, 23) to (2, 24) => {
          Global X
        }] |}]

let%expect_test "interface_extends_tparam" =
  print_ssa_test {|
type X<S> = S;

interface T<X> extends X<X> {
  x: X
};
|};
    [%expect {|
      [
        (2, 12) to (2, 13) => {
          (2, 7) to (2, 8): (`S`)
        };
        (4, 23) to (4, 24) => {
          (2, 5) to (2, 6): (`X`)
        };
        (4, 25) to (4, 26) => {
          (4, 12) to (4, 13): (`X`)
        };
        (5, 5) to (5, 6) => {
          (4, 12) to (4, 13): (`X`)
        }] |}]

let%expect_test "fun_type_tparam" =
  print_ssa_test {|
type T<W> = <X: W, Y: X>(X) => Y
|};
    [%expect {|
      [
        (2, 16) to (2, 17) => {
          (2, 7) to (2, 8): (`W`)
        };
        (2, 22) to (2, 23) => {
          (2, 13) to (2, 14): (`X`)
        };
        (2, 25) to (2, 26) => {
          (2, 13) to (2, 14): (`X`)
        };
        (2, 31) to (2, 32) => {
          (2, 19) to (2, 20): (`Y`)
        }] |}]

let%expect_test "class_tparam" =
  print_ssa_test {|
class C<X, Y:X> extends X<X> implements Y<Y> {
  f<Z:Y>(x:X, y:Y) {
    let z: Z;
  }
}
|};
    [%expect {|
      [
        (2, 13) to (2, 14) => {
          (2, 8) to (2, 9): (`X`)
        };
        (2, 24) to (2, 25) => {
          Global X
        };
        (2, 26) to (2, 27) => {
          (2, 8) to (2, 9): (`X`)
        };
        (2, 40) to (2, 41) => {
          Global Y
        };
        (2, 42) to (2, 43) => {
          (2, 11) to (2, 12): (`Y`)
        };
        (3, 6) to (3, 7) => {
          (2, 11) to (2, 12): (`Y`)
        };
        (3, 11) to (3, 12) => {
          (2, 8) to (2, 9): (`X`)
        };
        (3, 16) to (3, 17) => {
          (2, 11) to (2, 12): (`Y`)
        };
        (4, 11) to (4, 12) => {
          (3, 4) to (3, 5): (`Z`)
        }] |}]

let%expect_test "declare_class_tparam" =
  print_ssa_test {|
declare class C<X, Y:X, Z = X> extends X<X> mixins Z<Z> implements Y<Y> {
  f<Z:Y>(X, Y): Z;
}
|};
    [%expect {|
      [
        (2, 21) to (2, 22) => {
          (2, 16) to (2, 17): (`X`)
        };
        (2, 28) to (2, 29) => {
          (2, 16) to (2, 17): (`X`)
        };
        (2, 39) to (2, 40) => {
          Global X
        };
        (2, 41) to (2, 42) => {
          (2, 16) to (2, 17): (`X`)
        };
        (2, 51) to (2, 52) => {
          Global Z
        };
        (2, 53) to (2, 54) => {
          (2, 24) to (2, 25): (`Z`)
        };
        (2, 67) to (2, 68) => {
          Global Y
        };
        (2, 69) to (2, 70) => {
          (2, 19) to (2, 20): (`Y`)
        };
        (3, 6) to (3, 7) => {
          (2, 19) to (2, 20): (`Y`)
        };
        (3, 9) to (3, 10) => {
          (2, 16) to (2, 17): (`X`)
        };
        (3, 12) to (3, 13) => {
          (2, 19) to (2, 20): (`Y`)
        };
        (3, 16) to (3, 17) => {
          (3, 4) to (3, 5): (`Z`)
        }] |}]

let%expect_test "class_expr_tparam" =
  print_ssa_test {|
var w = class <X, Y:X> extends X<X> implements Y<Y> {
  f<Z:Y>(x:X, y:Y) {
    let z: Z;
  }
}
|};
    [%expect {|
      [
        (2, 20) to (2, 21) => {
          (2, 15) to (2, 16): (`X`)
        };
        (2, 31) to (2, 32) => {
          Global X
        };
        (2, 33) to (2, 34) => {
          (2, 15) to (2, 16): (`X`)
        };
        (2, 47) to (2, 48) => {
          Global Y
        };
        (2, 49) to (2, 50) => {
          (2, 18) to (2, 19): (`Y`)
        };
        (3, 6) to (3, 7) => {
          (2, 18) to (2, 19): (`Y`)
        };
        (3, 11) to (3, 12) => {
          (2, 15) to (2, 16): (`X`)
        };
        (3, 16) to (3, 17) => {
          (2, 18) to (2, 19): (`Y`)
        };
        (4, 11) to (4, 12) => {
          (3, 4) to (3, 5): (`Z`)
        }] |}]

let%expect_test "import_type" =
  print_ssa_test {|
var x: S;
import { type S } from '';
|};
    [%expect {|
      [
        (2, 7) to (2, 8) => {
          (3, 14) to (3, 15): (`S`)
        }] |}]

let%expect_test "import_mix" =
  print_ssa_test {|
var x: S = t;
var a: W;
import { type S, t, w as y, typeof w as W } from '';
t;
y;
w;
|};
    [%expect {|
      [
        (2, 7) to (2, 8) => {
          (4, 14) to (4, 15): (`S`)
        };
        (2, 11) to (2, 12) => {
          (uninitialized)
        };
        (3, 7) to (3, 8) => {
          (4, 40) to (4, 41): (`W`)
        };
        (5, 0) to (5, 1) => {
          (4, 17) to (4, 18): (`t`)
        };
        (6, 0) to (6, 1) => {
          (4, 25) to (4, 26): (`y`)
        };
        (7, 0) to (7, 1) => {
          Global w
        }] |}]

let%expect_test "import_def" =
  print_ssa_test {|
(NS: NST);
(ps: ns);
(ps: ms);
(1: a);
(2: b);
import type {a, b} from ''
import typeof ns from '';
import type ms from '';
import ps from ''
import * as NS from ''
import typeof * as NST from ''
(NS: NST);
(ps: ns);
(ps: ms);
(1: a);
(2: b);
|};
    [%expect {|
      [
        (2, 1) to (2, 3) => {
          (uninitialized)
        };
        (2, 5) to (2, 8) => {
          (12, 19) to (12, 22): (`NST`)
        };
        (3, 1) to (3, 3) => {
          (uninitialized)
        };
        (3, 5) to (3, 7) => {
          (8, 14) to (8, 16): (`ns`)
        };
        (4, 1) to (4, 3) => {
          (uninitialized)
        };
        (4, 5) to (4, 7) => {
          (9, 12) to (9, 14): (`ms`)
        };
        (5, 4) to (5, 5) => {
          (7, 13) to (7, 14): (`a`)
        };
        (6, 4) to (6, 5) => {
          (7, 16) to (7, 17): (`b`)
        };
        (13, 1) to (13, 3) => {
          (11, 12) to (11, 14): (`NS`)
        };
        (13, 5) to (13, 8) => {
          (12, 19) to (12, 22): (`NST`)
        };
        (14, 1) to (14, 3) => {
          (10, 7) to (10, 9): (`ps`)
        };
        (14, 5) to (14, 7) => {
          (8, 14) to (8, 16): (`ns`)
        };
        (15, 1) to (15, 3) => {
          (10, 7) to (10, 9): (`ps`)
        };
        (15, 5) to (15, 7) => {
          (9, 12) to (9, 14): (`ms`)
        };
        (16, 4) to (16, 5) => {
          (7, 13) to (7, 14): (`a`)
        };
        (17, 4) to (17, 5) => {
          (7, 16) to (7, 17): (`b`)
        }] |}]

let%expect_test "inc" =
  print_ssa_test {|
let x = 0;
++x;
x++;
x;
  |};
  [%expect {|
    [
      (3, 2) to (3, 3) => {
        (2, 4) to (2, 5): (`x`)
      };
      (4, 0) to (4, 1) => {
        (3, 2) to (3, 3): (`x`)
      };
      (5, 0) to (5, 1) => {
        (4, 0) to (4, 1): (`x`)
      }] |}]

let%expect_test "inc_heap" =
  print_ssa_test {|
let x = { a: 0 };
++x.a;
x.a++;
x.a;
  |};
  [%expect {|
    [
      (3, 2) to (3, 3) => {
        (2, 4) to (2, 5): (`x`)
      };
      (4, 0) to (4, 1) => {
        (2, 4) to (2, 5): (`x`)
      };
      (4, 0) to (4, 3) => {
        (3, 2) to (3, 5): (some property)
      };
      (5, 0) to (5, 1) => {
        (2, 4) to (2, 5): (`x`)
      };
      (5, 0) to (5, 3) => {
        (4, 0) to (4, 3): (some property)
      }] |}]

let%expect_test "op_assign_heap" =
  print_ssa_test {|
let x = { a: 0 };
x.a += 42;
x.a;
  |};
  [%expect {|
    [
      (3, 0) to (3, 1) => {
        (2, 4) to (2, 5): (`x`)
      };
      (4, 0) to (4, 1) => {
        (2, 4) to (2, 5): (`x`)
      };
      (4, 0) to (4, 3) => {
        (3, 0) to (3, 3): (some property)
      }] |}]

let%expect_test "class1" =
  print_ssa_test {|
(C: void); // as a value, C is undefined and in the TDZ

declare var c: C; // as a type, C refers to the class below
c.foo;

class C {
    foo: number;
}
  |};
  [%expect {|
    [
      (2, 1) to (2, 2) => {
        (uninitialized class) (7, 6) to (7, 7): (`C`)
      };
      (4, 15) to (4, 16) => {
        (uninitialized class) (7, 6) to (7, 7): (`C`)
      };
      (5, 0) to (5, 1) => {
        (4, 12) to (4, 13): (`c`)
      }] |}]

let%expect_test "class2" =
  print_ssa_test {|
class C {
  foo: D;
}
class D extends C {
  bar;
}
  |};
  [%expect {|
    [
      (3, 7) to (3, 8) => {
        (uninitialized class) (5, 6) to (5, 7): (`D`)
      };
      (5, 16) to (5, 17) => {
        (2, 6) to (2, 7): (`C`)
      }] |}]

let%expect_test "class3" =
  print_ssa_test {|
C;
class C {
  x: C;
}
C;
  |};
  [%expect {|
    [
      (2, 0) to (2, 1) => {
        (uninitialized class) (3, 6) to (3, 7): (`C`)
      };
      (4, 5) to (4, 6) => {
        (3, 6) to (3, 7): (`C`)
      };
      (6, 0) to (6, 1) => {
        (3, 6) to (3, 7): (`C`)
      }] |}]

let%expect_test "class4" =
  print_ssa_test {|

function havoced() {
  C;
}

class C {
}
  |};
  [%expect {|
    [
      (4, 2) to (4, 3) => {
        (7, 6) to (7, 7): (`C`)
      }] |}]

let%expect_test "class5" =
  print_ssa_test {|

function havoc() {
  C = 42;
}

havoc();
C;

class C {
}
  |};
  [%expect {|
    [
      (7, 0) to (7, 5) => {
        (3, 9) to (3, 14): (`havoc`)
      };
      (8, 0) to (8, 1) => {
        (uninitialized class) (10, 6) to (10, 7): (`C`),
        (10, 6) to (10, 7): (`C`)
      }] |}]

let%expect_test "deps_recur_broken_init" =
  print_ssa_test {|
type T = number;
let x: T;
function f() {
  x = x;
}
  |};
  [%expect {|
    [
      (3, 7) to (3, 8) => {
        (2, 5) to (2, 6): (`T`)
      };
      (5, 6) to (5, 7) => {
        (3, 4) to (3, 5): (`x`)
      }] |}]

let%expect_test "class3" =
  print_ssa_test {|
class C {
  foo: D;
}
class D extends C {
  bar;
}
  |};
  [%expect {|
    [
      (3, 7) to (3, 8) => {
        (uninitialized class) (5, 6) to (5, 7): (`D`)
      };
      (5, 16) to (5, 17) => {
        (2, 6) to (2, 7): (`C`)
      }] |}]

let%expect_test "enum" =
  print_ssa_test {|
function havoced() {
  var x: E = E.Foo
}
enum E {
  Foo
}
  |};
  [%expect {|
    [
      (3, 9) to (3, 10) => {
        (5, 5) to (5, 6): (`E`)
      };
      (3, 13) to (3, 14) => {
        (5, 5) to (5, 6): (`E`)
      }] |}]