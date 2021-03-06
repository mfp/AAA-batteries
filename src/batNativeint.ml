(* 
 * ExtNativeInt - Extended native ints
 * Copyright (C) 2005 Damien Doligez
 *               2007 Bluestorm <bluestorm dot dylc on-the-server gmail dot com>
 *               2008 David Teller
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


open BatNumber

module BaseNativeint = struct
  include Nativeint

  let modulo = rem
  let pow = generic_pow ~zero ~one ~div_two:(fun n -> shift_right n 1) ~mod_two:(logand one) ~mul
  let min_num, max_num = min_int, max_int
end

  include BatNumber.MakeNumeric(BaseNativeint)
  include BaseNativeint


  let print out t = BatInnerIO.Printf.fprintf out "%nx" t
  let t_printer paren out t = print out t
  let ( -- )  x y = BatEnum.seq x (add one) ((>=) y)
  let ( --- ) x y = 
    if x <= y then x -- y 
    else BatEnum.seq x pred ((<=) y) 
