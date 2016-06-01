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

open Format_types
open Cil_types

exception Type_not_found of string
exception Invalid_specifier

type arg_dir = [ `ArgIn | `ArgInArray | `ArgOut | `ArgOutArray ]

type typdef_finder = Logic_typing.type_namespace -> string -> Cil_types.typ

val type_f_specifier : ?find_typedef : typdef_finder -> f_conversion_specification -> typ
val type_s_specifier : ?find_typedef : typdef_finder -> s_conversion_specification -> typ
val type_f_format : ?find_typedef : typdef_finder ->  f_format -> (typ * arg_dir) list
val type_s_format : ?find_typedef : typdef_finder ->  s_format -> (typ * arg_dir) list
val type_format : ?find_typedef : typdef_finder -> format -> (typ * arg_dir) list

