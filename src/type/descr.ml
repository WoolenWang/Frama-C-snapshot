(**************************************************************************)
(*                                                                        *)
(*  This file is part of Frama-C.                                         *)
(*                                                                        *)
(*  Copyright (C) 2007-2011                                               *)
(*    CEA (Commissariat � l'�nergie atomique et aux �nergies              *)
(*         alternatives)                                                  *)
(*                                                                        *)
(*  you can redistribute it and/or modify it under the terms of the GNU   *)
(*  Lesser General Public License as published by the Free Software       *)
(*  Foundation, version 2.1.                                              *)
(*                                                                        *)
(*  It is distributed in the hope that it will be useful,                 *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of        *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *)
(*  GNU Lesser General Public License for more details.                   *)
(*                                                                        *)
(*  See the GNU Lesser General Public License version 2.1                 *)
(*  for more details (enclosed in the file licenses/LGPLv2.1).            *)
(*                                                                        *)
(**************************************************************************)

open Structural_descr

(* ********************************************************************** *)
(** {2 Type declaration} *)
(* ********************************************************************** *)

type 'a t = pack

let coerce d = (d : single_pack :> Unmarshal.t)

(* ********************************************************************** *)
(** {2 Predefined type descriptors} *)
(* ********************************************************************** *)

let unmarshable = pack Unknown
let is_unmarshable x = x = unmarshable

let t_unit = unsafe_pack Unmarshal.t_unit
let t_int = unsafe_pack Unmarshal.t_int
let t_string = unsafe_pack Unmarshal.t_string
let t_float = unsafe_pack Unmarshal.t_float
let t_bool = unsafe_pack Unmarshal.t_bool
let t_int32 = unsafe_pack Unmarshal.t_int32
let t_int64 = unsafe_pack Unmarshal.t_int64
let t_nativeint = unsafe_pack Unmarshal.t_nativeint

(* ********************************************************************** *)
(** {2 Type descriptor builders} *)
(* ********************************************************************** *)

exception Invalid_descriptor = Cannot_pack

(** {3 Builders for standard OCaml types} *)

let t_record x _ =
  try
    let x =
      Array.map
	(fun x -> match x with
	| Nopack | Recursive _ -> raise Invalid_descriptor
	| Pack x -> coerce x)
	x
    in
    unsafe_pack (Unmarshal.t_record x)
  with Cannot_pack ->
    unmarshable

let t_tuple = t_record
let t_pair x y = match x, y with
  | (Nopack | Recursive _), _ | _, (Nopack | Recursive _) -> unmarshable
  | Pack x, Pack y -> unsafe_pack (Unmarshal.t_tuple [| coerce x; coerce y |])

let t_poly f = function
  | Nopack -> unmarshable
  | Recursive _ -> raise Invalid_descriptor
  | Pack x -> unsafe_pack (f (coerce x))

let t_list = t_poly Unmarshal.t_list
let t_ref = t_poly Unmarshal.t_ref
let t_option = t_poly Unmarshal.t_option
let t_queue = t_poly Unmarshal.t_queue

(** {3 Builders from others datatypes of the Type library} *)

let of_type ty = pack (Type.structural_descr ty)
let of_structural ty d =
  if Structural_descr.are_consistent (Type.structural_descr ty) d then
    pack d
  else
    invalid_arg "Descr.of_structural: inconsistent descriptor"

(** {3 Builders mapping transformers of {!Unmarshal}} *)

let rec dependent_pair a fb = match a with
  | Nopack -> unmarshable
  | Recursive _ -> raise Invalid_descriptor
  | Pack a ->
    let f x = match fb (Obj.obj x) with
      | Nopack | Recursive _ -> raise Invalid_descriptor
      | Pack b -> coerce b
    in
    unsafe_pack (Unmarshal.Structure (Unmarshal.Dependent_pair (coerce a, f)))

let return d f = match d with
  | Nopack -> unmarshable
  | Recursive _ -> raise Invalid_descriptor
  | Pack d ->
    unsafe_pack (Unmarshal.Return(coerce d, (fun x -> Obj.repr (f x))))

let dynamic f =
  let f () = match f () with
    | Nopack | Recursive _ -> raise Invalid_descriptor
    | Pack y -> coerce y
  in
  unsafe_pack (Unmarshal.Dynamic f)

module Unmarshal_tbl =
  Hashtbl.Make
    (struct
      type t = Unmarshal.t
      let equal = (==)
      let hash = Hashtbl.hash
     end)

let visited = Unmarshal_tbl.create 7

let rec transform_unmarshal_structure term x = function
  | Unmarshal.Sum arr ->
    let l = ref [] in
    Array.iter
      (fun a ->
	Array.iteri
	  (fun i y ->
	    if x == y then l := (a, i) :: !l else transform_unmarshal term x y)
	  a)
      arr;
    List.iter (fun (a, i) -> a.(i) <- term) !l
  | Unmarshal.Dependent_pair(d, _) | Unmarshal.Array d ->
    transform_unmarshal term x d

and transform_unmarshal term x = function
  | Unmarshal.Abstract | Unmarshal.Dynamic _ -> ()
  | Unmarshal.Structure s as y ->
    if not (Unmarshal_tbl.mem visited y) then begin
      Unmarshal_tbl.add visited y ();
      transform_unmarshal_structure term x s
    end
  | Unmarshal.Return(d, _) | Unmarshal.Transform(d, _) as y ->
    (* TODO: not possible to change the return/transform by [term] if its ==
       to [x] (since this value is immutable). Hopefully this case should never
       occur. *)
    assert (x != y);
    transform_unmarshal term x d

let rec transform descr f = match descr with
  | Nopack -> raise Cannot_pack
  | Recursive _ -> raise Invalid_descriptor
  | Pack d ->
    let d = coerce d in
    let term = Unmarshal.Transform(d, fun x -> Obj.repr (f (Obj.obj x))) in
    transform_unmarshal term d d;
    Unmarshal_tbl.clear visited;
    unsafe_pack term

(* ********************************************************************** *)
(** {2 Coercions} *)
(* ********************************************************************** *)

let str = function
  | Nopack -> Unknown
  | Pack p -> T_pack p
  | Recursive _ -> raise Invalid_descriptor

let pack x = x

(* ********************************************************************** *)
(** {2 Safe unmarshaling} *)
(* ********************************************************************** *)

let input_val cin = function
  | Nopack | Recursive _ -> invalid_arg "Descr.input_val: unmarshable value"
  | Pack d -> Unmarshal.input_val cin (coerce d)

(*
Local Variables:
compile-command: "make -C ../.."
End:
*)