module type S = sig

  type key
  type 'a item
  type 'a t

  val get : 'a item -> 'a
  val get_key : 'a item -> key
  val live : 'a item -> bool

  val create : unit -> 'a t
  val insert : 'a t -> key -> 'a -> 'a item
  val merge : 'a t -> 'a t -> unit
  val find_min : 'a t -> 'a item option
  val delete_min : 'a t -> unit
  val decrease_key : 'a t -> 'a item -> key -> unit

end

module Make (Ord:Map.OrderedType) = struct

  type key = Ord.t

  type 'a holloption =
    | Full of key * 'a
    | Hollow

  (** Non-empty heaps are in the form of a rooted dag (where each node
      has at most two parent). The module [Node] implements the logic
      for non-empty heap. Only [delete_min] is not straightforward. *)
  module Node = struct

    type 'a t = {
      mutable elt : 'a item holloption;
      (** Children are mutable in particular to allow dag-shaped
          heaps. May possibly be improved by "inlining" the list as
          two field "child" and "next" both of type ['a t] as
          described in Section 6 of the original article. *)
      mutable children : 'a t list;
      (** [rank] is used to guide the linking strategy during
          deletes. It is a non-negative int. *)
      mutable rank : int;
      (** [sp] is the "second parent" of this node if it has one
          (second parents are inserted by {!link_above}, itself called
          in {!decrease_key}).*)
      mutable sp : 'a t option;
    }
    (** ['a item] point back to the node which hold them. They are
        used by {!decrease_key} to find the node whose key to
        decrease. It is an invariant that [xi.node] always point back
        to the unique node which contains [xi]. *)
    and 'a item = { self: 'a ; mutable node: 'a t ; mutable live: bool}

    (** {6 Helper functions} *)

    (** Used as a temporary place-holder for {!make}. *)
    (* TODO: producing a new value each time a node is inserted is
       safe, but presumably slow. It is probably desirable to use
       unsafe features (beware of not breaking flambda though) for the
       sake of efficiency. *)
    let dummy_node () = { elt = Hollow ; children = [] ; rank = 0 ; sp = None }

    (** Creates and returns a new node with item [xi] in it. Enforces
        the invariant that [xi] points back to that node. *)
    let make_with ?(rank=0) k xi =
      let u = { elt = Full (k,xi); children = [] ; rank ; sp = None } in
      let () = xi.node <- u in
      u

    (** Creates a new node with a fresh [item]. Returns both the node
        and the item. *)
    let make k x =
      let xi = { self = x ; node = dummy_node () ; live = true } in
      xi, make_with k xi

    (** Assigns the node of [u] and [v] with the larger key as a child
        of the other. *)
    let link u v =
      (* Remark: it is an invariant of nodes that the root is always full. *)
      match u.elt , v.elt with
      | Full (ku,_), Full (kv,_) ->
        if ku >= kv then
          let () = v.children <- u::v.children in
          v
        else
          let () = u.children <- v::u.children in
          u
      | _ -> assert false

    (** [link_above w u v] links [u] and [v] with the following
        assumptions: [v] is an ancestor of [w] and [u] has a smaller
        key than every full node which descend from [w]. So if [u] is
        placed below [v], we also add [w] as a child of [u] to record
        the assumption in the structure of the heap. My guess is that
        the more links there are, the less likely it is that [delete]
        be costly. Therefore it is worth it recording all the
        knowledge we have. *)
    let link_above w u v =
      match u.elt , v.elt with
      | Full (ku,_), Full (kv,_) ->
        if ku >= kv then
          let () = v.children <- u::v.children in
          let () = u.children <- w::u.children in
          let () = w.sp <- Some u in
          v
        else
          let () = u.children <- v::u.children in
          u
      | _ -> assert false

    (** Replaces the key of the {e root} [u] of a non-empty heap by
        [k]. Precondition: [k] must be no larger than the current key of
        [u]. *)
    let update_key u k =
      (* Remark: it is an invariant of nodes the root is always
         full.*)
      match u.elt with
      | Full (k0,xi) ->
        assert (k0 >= k);
        u.elt <- Full (k,xi)
      | _ -> assert false

    (** {6 Heap operations (except delete-min)} *)

    let merge = link

    let insert u k x =
      let (xi,v) = make k x in
      xi , merge v u

    let find_min u =
      (* Remark: it is an invariant of nodes that the root is always
         full. *)
      match u.elt with
      | Full (_,xi) -> xi
      | _ -> assert false

    let decrease_key ({ node=u } as xi) k h =
      if u == h then
        let () = update_key h k in
        h
      else
        let rank = max 0 (u.rank-2) in
        let v = make_with k xi ~rank in
        let () = u.elt <- Hollow in
        link_above u v h


    (** {6 Delete min} *)

    (** A variant of {!link} which updates the [rank]. See the
        original article for an explanation. *)
    let rank_link u v =
      let w = link u v in
      let () = w.rank <- w.rank + 1 in
      w

    (** This function is described in Section 6 of the original
        article. *)
    let delete_min u =
      (* Full should be a resizable array, but as a first
         approximation, since it's in the stdlib, I'm using a hash table
         instead. *)
      let full = Hashtbl.create 42 in
      let merge_left h = function
        | None -> h
        | Some u -> link h u
      in
      let link_all () =
        (* There is a lot of useless boxing here. Maybe there is a way
           to make it shorter. *)
        Hashtbl.fold (fun _ h acc -> Some (merge_left h acc)) full None
      in
      let rec push h =
        match Hashtbl.find full h.rank with
        | u ->
          Hashtbl.remove full h.rank;
          push (rank_link h u)
        | exception Not_found ->
          Hashtbl.add full h.rank h
      in
      let rec triage hollow root = function
        | [] -> hollow
        | c::rest ->
          begin match c.elt with
            | Full _ ->
              let () = push c in
              triage hollow root rest
            | Hollow ->
              (* TODO: in this presentation, it seems that this could
                 be simplified: we only need to "reference count" the
                 parents (since there is at most two parents, we only
                 need a boolean) instead of keeping a "second parent
                 pointer". Indeed the two last branch seem to do the
                 exact same thing. *)
              match c.sp with
              | None -> triage (c::hollow) root rest
              | Some u when u==root -> (* [root] is the second parent *)
                assert (rest==[]);
                c.sp <- None;
                hollow
              | Some u -> (* [root] is the first parent. *)
                c.sp <- None;
                triage hollow root rest
          end
      in
      let rec process_hollow hollow =
        match hollow with
        | [] -> link_all ()
        | h::l ->
          (* Invariant: the root of [h] is hollow *)
          let hollow = triage l h h.children in
          process_hollow hollow
      in
      let () =
        match u.elt with
        | Full (_,xi) ->
          (* [xi] is being removed from [h], so it's not live
             anymore. *)
          xi.live <- false;
          (* Free the node to avoid space leaks. *)
          xi.node <- dummy_node ();
        | Hollow -> assert false
      in
      let hollow = triage [] u u.children in
      process_hollow hollow

  end

  type 'a item = 'a Node.item

  let get { Node.self } = self

  let get_key { Node.node=u } =
    match u.Node.elt with
    | Full(k,_) -> k
    | Hollow -> assert false

  let live { Node.live } = live

  type 'a t = 'a Node.t option ref

  let create () = ref None

  let insert h k x =
    match !h with
    | None ->
      let (xi,u) = Node.make k x in
      let () = h := Some u in
      xi
    | Some v ->
      let (xi,u) = Node.insert v k x in
      let () = h := Some u in
      xi

  let swap r1 r2 =
    let temp = !r1 in
    r1 := !r2;
    r2 := temp

  let merge h1 h2 =
    match !h1,!h2 with
    | _ , None -> ()
    | None , _ -> swap h1 h2
    | Some u, Some v ->
      h1 := Some (Node.merge u v);
      h2 := None

  let find_min h =
    match !h with
    | None -> None
    | Some u -> Some (Node.find_min u)

  let delete_min h =
    match !h with
    | None -> ()
    | Some u -> h := Node.delete_min u

  let decrease_key h xi k =
    match !h with
    | None -> assert false
    | Some u -> h := Some (Node.decrease_key xi k u)

end
