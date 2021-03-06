(**************************************************************************)
(*                                                                        *)
(*  This file is part of Frama-C.                                         *)
(*                                                                        *)
(*  Copyright (C) 2007-2016                                               *)
(*    CEA (Commissariat à l'énergie atomique et aux énergies              *)
(*         alternatives)                                                  *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  Contact CEA LIST for licensing.                                       *)
(*                                                                        *)
(**************************************************************************)

open Eval

let counter = ref 0

module Make
    (Value: Abstract_value.S)
    (Left:  Abstract_domain.Internal with type value = Value.t)
    (Right: Abstract_domain.Internal with type value = Left.value
                                      and type location = Left.location)
= struct

  type value = Left.value
  type location = Left.location

  type origin = {
    left:  reductness * Left.origin;
    right: reductness * Right.origin;
  }

  let () = incr counter
  let name = Left.name ^ "*" ^ Right.name ^
             "(" ^ string_of_int !counter ^ ")"

  include Datatype.Pair_with_collections
      (Left)
      (Right)
      (struct let module_name = name end)
  type state = t

  let structure = Abstract_domain.Node (Left.structure, Right.structure)

  let top = Left.top, Right.top
  let is_included (left1, right1) (left2, right2) =
    Left.is_included left1 left2 && Right.is_included right1 right2
  let join (left1, right1) (left2, right2) =
    Left.join left1 left2, Right.join right1 right2
  let join_and_is_included (left1, right1) (left2, right2) =
    let left, b1 = Left.join_and_is_included left1 left2
    and right, b2 = Right.join_and_is_included right1 right2 in
    (left, right), b1 && b2
  let widen kf stmt (left1, right1) (left2, right2) =
    Left.widen kf stmt left1 left2, Right.widen kf stmt right1 right2


  let merge (eval1, alarms1) (eval2, alarms2) =
    match Alarmset.inter alarms1 alarms2 with
    | `Inconsistent ->
      Value_parameters.abort ~current:true ~once:true
        "Inconsistent status of alarms: unsound states."
    | `Value alarms ->
      let value =
        eval1 >>- fun (v1, o1) ->
        eval2 >>- fun (v2, o2) ->
        Value.narrow v1 v2 >>-: fun value ->
        let left =
          if Value.equal value v1 then Unreduced
          else if Value.equal v1 Value.top then Created else Reduced
        and right =
          if Value.equal value v2 then Unreduced
          else if Value.equal v2 Value.top then Created else Reduced
        in
        let origin = {left = left, o1; right = right, o2} in
        value, origin
      in
      value, alarms

  let extract_expr oracle (left, right) expr =
    merge
      (Left.extract_expr oracle left expr)
      (Right.extract_expr oracle right expr)

  let extract_lval oracle (left, right) lval typ location =
    merge
      (Left.extract_lval oracle left lval typ location)
      (Right.extract_lval oracle right lval typ location)

  let backward_location (left, right) lval typ loc value =
    (* TODO: Loc.narrow *)
    Left.backward_location left lval typ loc value >>- fun (loc, value1) ->
    Right.backward_location right lval typ loc value >>- fun (loc, value2) ->
    Value.narrow value1 value2 >>-: fun value ->
    loc, value

  let reduce_further (left, right) expr value =
    List.append
      (Left.reduce_further left expr value)
      (Right.reduce_further right expr value)


  let merge_values left right =
    let v =
      left.v >>- fun l -> right.v >>- fun r ->
      Value.narrow l r
    and initialized = left.initialized || right.initialized
    and escaping = left.escaping && right.escaping in
    { v; initialized; escaping }

  let merge_init left right =
    match left, right with
    | Default, Default -> Default
    | Continue left, Continue right -> Continue (left, right)
    | Default, Continue right       -> Continue (Left.top, right)
    | Continue left, Default        -> Continue (left, Right.top)
    | _, _ -> assert false (* TODO! *)

  let merge_return _kf left right =
    let post_state = left.post_state, right.post_state
    and summary = left.summary, right.summary
    and returned_value =
      match left.returned_value, right.returned_value with
      | None, None            -> None
      | Some left, Some right -> Some (merge_values left right)
      | Some x, None
      | None, Some x -> Some x (* TODO! *)
        (*
        Format.printf "Function %a@." Kernel_function.pretty kf;
        Value_parameters.abort ~current:true ~once:true
          "Return value present in right domain and not in left domain."
        *)
    in
    { post_state; returned_value; summary }

  let merge_results kf left_list right_list =
    List.fold_left
      (fun acc left ->
         List.fold_left
           (fun acc right -> merge_return kf left right :: acc)
           acc right_list)
      [] left_list



  module Summary = Datatype.Pair (Left.Summary) (Right.Summary)
  type summary = Summary.t

  module Transfer
      (Valuation: Abstract_domain.Valuation with type value = value
                                             and type origin = origin
                                             and type loc = location)
  = struct

    type state = t
    type summary = Summary.t
    type value = Value.t
    type location = Left.location
    type valuation = Valuation.t

    module type Lift = sig
      type o
      val side : origin -> reductness * o
    end

    module Lift_Valuation (Lift: Lift) = struct
      type t = Valuation.t
      type value = Value.t
      type origin = Lift.o
      type loc = Valuation.loc

      let lift_record record =
        let origin = Extlib.opt_map Lift.side record.origin in
        let reductness =
          match record.reductness, origin with
          | Unreduced, Some (reduced, _) -> reduced
          | Unreduced, None -> Unreduced (* This case should not happen. *)
          | Reduced, Some (Created, _) -> Created
          | _ as x, _ -> x
        in
        let origin = Extlib.opt_map snd origin in
        { record with origin; reductness }

      let find valuation expr = match Valuation.find valuation expr with
        | `Value record -> `Value (lift_record record)
        | `Top -> `Top

      let fold f valuation acc =
        Valuation.fold
          (fun exp record acc -> f exp (lift_record record) acc)
          valuation acc

      let find_loc = Valuation.find_loc
    end

    module Left_Valuation =
      Lift_Valuation (struct type o = Left.origin let side o = o.left end)
    module Right_Valuation =
      Lift_Valuation (struct type o = Right.origin let side o = o.right end)

    module Left_Transfer = Left.Transfer (Left_Valuation)
    module Right_Transfer = Right.Transfer (Right_Valuation)

    let update valuation (left, right) =
      Left_Transfer.update valuation left,
      Right_Transfer.update valuation right

    let assign stmt lv expr value valuation (left, right) =
      Left_Transfer.assign stmt lv expr value valuation left >>- fun left ->
      Right_Transfer.assign stmt lv expr value valuation right >>-: fun right ->
      left, right

    let assume stmt expr positive valuation (left, right) =
      Left_Transfer.assume stmt expr positive valuation left >>- fun left ->
      Right_Transfer.assume stmt expr positive valuation right >>-: fun right ->
      left, right

    let summarize kf stmt ~returned (left, right) =
      Left_Transfer.summarize kf stmt ~returned left
      >>- fun (left_summary, left_state) ->
      Right_Transfer.summarize kf stmt ~returned right
      >>-: fun (right_summary, right_state) ->
      (left_summary, right_summary), (left_state, right_state)

    let resolve_call stmt call ~assigned valuation ~pre ~post =
      let pre_left, pre_right = pre
      and (left_summary, right_summary), (left_state, right_state) = post in
      Left_Transfer.resolve_call stmt call ~assigned valuation
        ~pre:pre_left ~post:(left_summary, left_state)
      >>- fun left ->
      Right_Transfer.resolve_call stmt call ~assigned valuation
        ~pre:pre_right ~post:(right_summary, right_state)
      >>-: fun right ->
      left, right

    let default_call stmt call (left, right) =
      Left_Transfer.default_call stmt call left >>- fun left_result ->
      Right_Transfer.default_call stmt call right >>-: fun right_result ->
      merge_results call.kf left_result right_result

    let call_action stmt call valuation (left, right) =
      let left_action = Left_Transfer.call_action stmt call valuation left
      and right_action = Right_Transfer.call_action stmt call valuation right in
      match left_action, right_action with
      | Compute (left_init, b), Compute (right_init, b') ->
        Compute (merge_init left_init right_init, b && b')
      | Result (left_result, c1), Result (right_result, _c2) ->
        let result =
          left_result >>- fun left_result ->
          right_result >>-: fun right_result ->
          merge_results call.kf left_result right_result
        in
        Result (result, c1) (* TODO: c1 *)
      | Result (left_result, c1), _ ->
        let result =
          Right_Transfer.default_call stmt call right >>- fun right_result ->
          left_result >>-: fun left_result ->
          merge_results call.kf left_result right_result
        in
        Result (result, c1)
      | _, Result (right_result, c2) ->
        let result =
          Left_Transfer.default_call stmt call left >>- fun left_result ->
          right_result >>-: fun right_result ->
          merge_results call.kf left_result right_result
        in
        Result (result, c2)
      | _, _ -> assert false

  end


  (* TODO *)
  let compute_using_specification kinstr kf (left, right) =
    Left.compute_using_specification kinstr kf left >>- fun left ->
    Right.compute_using_specification kinstr kf right >>-: fun right ->
    merge_results (fst kf) left right


  type eval_env = Left.eval_env * Right.eval_env

  let env_current_state (left, right) =
    Left.env_current_state left >>- fun left_env ->
    Right.env_current_state right >>-: fun right_env ->
    left_env, right_env

  let env_annot ~pre ~here () =
    Left.env_annot ~pre:(fst pre) ~here:(fst here) (),
    Right.env_annot ~pre:(snd pre) ~here:(snd here) ()

  let env_pre_f ~pre () =
    Left.env_pre_f ~pre:(fst pre) (), Right.env_pre_f ~pre:(snd pre) ()

  let env_post_f ~pre ~post ~result () =
    Left.env_post_f ~pre:(fst pre) ~post:(fst post) ~result (),
    Right.env_post_f ~pre:(snd pre) ~post:(snd post) ~result ()

  let eval_predicate (left, right) pred =
    let status =
      Alarmset.Status.inter
        (Left.eval_predicate left pred) (Right.eval_predicate right pred)
    in
    match status with
    | `Inconsistent ->
      Value_parameters.abort ~current:true ~once:true
        "Inconsistent status of alarms: unsound states."
    | `Value status -> status

  let reduce_by_predicate (left, right) positive pred =
    Left.reduce_by_predicate left positive pred,
    Right.reduce_by_predicate right positive pred


  let close_block fundec block ~body (left, right) =
    Left.close_block fundec block ~body left,
    Right.close_block fundec block ~body right
  let open_block fundec block ~body (left, right) =
    Left.open_block fundec block ~body left,
    Right.open_block fundec block ~body right


  let empty () = Left.empty (), Right.empty ()
  let initialize_var (left, right) lval loc value =
    Left.initialize_var left lval loc value,
    Right.initialize_var right lval loc value
  let initialize_var_using_type (left, right) varinfo =
    Left.initialize_var_using_type left varinfo,
    Right.initialize_var_using_type right varinfo
  (* TODO *)
  let global_state () = None


  let filter_by_bases bases (left, right) =
    Left.filter_by_bases bases left, Right.filter_by_bases bases right
  let reuse ~current_input ~previous_output =
    Left.reuse
      ~current_input:(fst current_input) ~previous_output:(fst previous_output),
    Right.reuse
      ~current_input:(snd current_input) ~previous_output:(snd previous_output)

end


(*
Local Variables:
compile-command: "make -C ../../../.."
End:
*)
