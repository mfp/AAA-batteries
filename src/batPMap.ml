(*
 * PMap - Polymorphic maps
 * Copyright (C) 1996-2003 Xavier Leroy, Nicolas Cannasse, Markus Mottl
 *               2009 David Rajchenbach-Teller, LIFO, Universite d'Orleans
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


type ('k, 'v) map =
  | Empty
  | Node of ('k, 'v) map * 'k * 'v * ('k, 'v) map * int

type ('k, 'v) t =
  {
    cmp : 'k -> 'k -> int;
    map : ('k, 'v) map;
  }

let height = function
  | Node (_, _, _, _, h) -> h
  | Empty -> 0

let make l k v r = Node (l, k, v, r, max (height l) (height r) + 1)

let bal l k v r =
  let hl = height l in
  let hr = height r in
  if hl > hr + 2 then
    match l with
    | Node (ll, lk, lv, lr, _) ->
        if height ll >= height lr then make ll lk lv (make lr k v r)
        else
          (match lr with
          | Node (lrl, lrk, lrv, lrr, _) ->
              make (make ll lk lv lrl) lrk lrv (make lrr k v r)
          | Empty -> assert false)
    | Empty -> assert false
  else if hr > hl + 2 then
    match r with
    | Node (rl, rk, rv, rr, _) ->
        if height rr >= height rl then make (make l k v rl) rk rv rr
        else
          (match rl with
          | Node (rll, rlk, rlv, rlr, _) ->
              make (make l k v rll) rlk rlv (make rlr rk rv rr)
          | Empty -> assert false)
    | Empty -> assert false
  else Node (l, k, v, r, max hl hr + 1)

let rec min_binding = function (* shadowed by definition at end of file *)
  | Node (Empty, k, v, _, _) -> k, v
  | Node (l, _, _, _, _) -> min_binding l
  | Empty -> raise Not_found

let rec remove_min_binding = function
  | Node (Empty, _, _, r, _) -> r
  | Node (l, k, v, r, _) -> bal (remove_min_binding l) k v r
  | Empty -> invalid_arg "PMap.remove_min_binding"

let merge t1 t2 =
  match t1, t2 with
  | Empty, _ -> t2
  | _, Empty -> t1
  | _ ->
      let k, v = min_binding t2 in
      bal t1 k v (remove_min_binding t2)

let create cmp = { cmp = cmp; map = Empty }
let empty = { cmp = compare; map = Empty }

let is_empty x = 
	x.map = Empty

let add x d { cmp = cmp; map = map } =
  let rec loop = function
    | Node (l, k, v, r, h) ->
        let c = cmp x k in
        if c = 0 then Node (l, x, d, r, h)
        else if c < 0 then
          let nl = loop l in
          bal nl k v r
        else
          let nr = loop r in
          bal l k v nr
    | Empty -> Node (Empty, x, d, Empty, 1) in
  { cmp = cmp; map = loop map }

let find x { cmp = cmp; map = map } =
  let rec loop = function
    | Node (l, k, v, r, _) ->
        let c = cmp x k in
        if c < 0 then loop l
        else if c > 0 then loop r
        else v
    | Empty -> raise Not_found in
  loop map

let remove x { cmp = cmp; map = map } =
  let rec loop = function
    | Node (l, k, v, r, _) ->
        let c = cmp x k in
        if c = 0 then merge l r else
        if c < 0 then bal (loop l) k v r else bal l k v (loop r)
    | Empty -> Empty in
  { cmp = cmp; map = loop map }

let mem x { cmp = cmp; map = map } =
  let rec loop = function
    | Node (l, k, v, r, _) ->
        let c = cmp x k in
        c = 0 || loop (if c < 0 then l else r)
    | Empty -> false in
  loop map

let exists = mem

let iter f { map = map } =
  let rec loop = function
    | Empty -> ()
    | Node (l, k, v, r, _) -> loop l; f k v; loop r in
  loop map

let map f { cmp = cmp; map = map } =
  let rec loop = function
    | Empty -> Empty
    | Node (l, k, v, r, h) -> 
	  let l = loop l in
	  let r = loop r in
	  Node (l, k, f v, r, h) in
  { cmp = cmp; map = loop map }

let mapi f { cmp = cmp; map = map } =
  let rec loop = function
    | Empty -> Empty
    | Node (l, k, v, r, h) ->
	  let l = loop l in
	  let r = loop r in
	  Node (l, k, f k v, r, h) in
  { cmp = cmp; map = loop map }

let fold f { cmp = cmp; map = map } acc =
  let rec loop acc = function
    | Empty -> acc
    | Node (l, k, v, r, _) ->
	  loop (f v (loop acc l)) r in
  loop acc map

let foldi f { cmp = cmp; map = map } acc =
  let rec loop acc = function
    | Empty -> acc
	| Node (l, k, v, r, _) ->
       loop (f k v (loop acc l)) r in
  loop acc map

let enum { map = map } =
  let rec loop e () = match e with
    | Empty -> BatEnum.empty ()
    | Node (l, k, v, r, _) ->
	BatEnum.flatten (BatList.enum [
			BatEnum.delay (loop l);
			BatEnum.singleton (k, v);
			BatEnum.delay (loop r)])
  in loop map ()
		       

(*let rec enum m =
  let rec make l =
    let l = ref l in
    let rec next() =
      match !l with
      | [] -> raise BatEnum.No_more_elements
      | Empty :: tl -> l := tl; next()
      | Node (m1, key, data, m2, h) :: tl ->
        l := m1 :: m2 :: tl;
        (key, data)
    in
    let count() =
      let n = ref 0 in
      let r = !l in
      try
        while true do
          ignore (next());
          incr n
        done;
        assert false
      with
		BatEnum.No_more_elements -> l := r; !n
    in
    let clone() = make !l in
	BatEnum.make ~next ~count ~clone
  in
  make [m.map]*)


let uncurry_add m (k, v) = add k v m
let of_enum ?(cmp = compare) e = BatEnum.fold uncurry_add (create cmp) e


let print ?(first="{\n") ?(last="\n}") ?(sep=",\n") print_k print_v out t =
  BatEnum.print ~first ~last ~sep (fun out (k,v) -> BatPrintf.fprintf out "%a: %a" print_k k print_v v) out (enum t)

let filter  f t = foldi (fun k a acc -> if f a then add k a acc else acc) t empty
let filteri f t = foldi (fun k a acc -> if f k a then add k a acc else acc) t empty
let filter_map f t = foldi (fun k a acc -> match f k a with
			     | None   -> acc
			     | Some v -> add k v acc)  t empty

let _choose = function   
  | Empty -> invalid_arg "PMap.choose: empty tree"
  | Node (_l,k,v,_r,_h) -> (k,v)

let choose t = _choose t.map

let rec max_binding = function (* shadowed by below definition *)
  | Node (_, k, v, Empty, _) -> k, v
  | Node (_, _, _, r, _) -> max_binding r
  | Empty -> invalid_arg "PMap.max_binding: empty tree"

let max_binding t = max_binding t.map (* shadows earlier definition *)

let min_binding t = min_binding t.map (* shadows earlier definition *)

let singleton ?(cmp = compare) k v = add k v (create cmp)

let for_all f { cmp = cmp; map = map } =
  let rec loop = function
    | Empty -> true
    | Node (l, k, v, r, _) ->
	  f k v && loop l && loop r in
  loop map

let exists_f f { cmp = cmp; map = map } =
  let rec loop = function
    | Empty -> false
    | Node (l, k, v, r, _) ->
	  f k v || loop l || loop r in
  loop map

let partition f { cmp = cmp; map = map } =
  let rec loop m1 m2 = function
    | Empty -> (m1,m2)
    | Node (l, k, v, r, _) ->
	let m1, m2 = loop m1 m2 l in
	let m1, m2 = loop m1 m2 r in
	if f k v then 
	  (add k v m1, m2)
	else
	  (m1, add k v m2)
  in
  loop (create cmp) (create cmp) map

let cardinal {cmp = cmp; map = map} =
  let rec loop acc = function
    | Empty -> acc
    | Node (l, _, _, r, _) ->
	loop (loop (acc+1) r) l 
  in
  loop 0 map

let choose {cmp = cmp; map = map} =
  match map with
    | Empty -> raise Not_found
    | Node (_, k, v, _, _) -> (k,v)


let add_carry x d { cmp = cmp; map = map } =
  let rec loop = function
    | Node (l, k, v, r, h) ->
        let c = cmp x k in
        if c = 0 then Node (l, x, d, r, h), Some v
        else if c < 0 then
          let nl,carry = loop l in
          bal nl k v r, carry
        else
          let nr, carry = loop r in
          bal l k v nr, carry
    | Empty -> Node (Empty, x, d, Empty, 1), None in
  let map, carry = loop map in
  { cmp = cmp; map = map }, carry

let modify x f ({ cmp = cmp; map = map } as m) =
  let rec loop = function
    | Node (l, k, v, r, h) ->
        let c = cmp x k in
        if c = 0 then Node (l, x, f v, r, h)
        else if c < 0 then
          let nl = loop l in
          bal nl k v r
        else
          let nr = loop r in
          bal l k v nr
    | Empty -> raise Not_found in
  try 
    { cmp = cmp; map = loop map }
  with Not_found -> m

let extract x { cmp = cmp; map = map } =
  let rec loop = function
    | Node (l, k, v, r, _) ->
        let c = cmp x k in
        if c = 0 then v, merge l r else
        if c < 0 then 
	  let vout, nl = loop l in
	  vout, bal nl k v r
	else 
	  let vout, nr = loop r in
	  vout, bal l k v nr
    | Empty -> raise Not_found in
  let vout, nmap = loop map in
  vout, { cmp = cmp; map = nmap }

let pop {cmp = cmp; map = map} =
  match map with
    | Empty -> raise Not_found
    | Node (l, k, v, r, _) ->
	(k, v), {cmp = cmp; map = merge l r}
