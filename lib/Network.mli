open Types
open Graph

module G : Sig.G
module V : Sig.VERTEX
module E : Sig.EDGE
type t
(* Constructors *)
val add_node : t -> V.t -> t
val add_host : t -> string -> Packet.dlAddr -> Packet.nwAddr -> int -> t
val add_switch : t -> switchId -> int -> t
val add_switch_edge : t -> V.t -> portId -> V.t -> portId -> t

(* Accessors *)
val get_vertices : t -> V.t list
val get_edges : t -> E.t list
val get_ports : t -> V.t -> V.t -> (portId * portId)
val get_hosts : t -> V.t list
val get_switches : t -> V.t list
val get_switchids : t -> switchId list
val unit_cost : t -> t
val ports_of_switch : t -> V.t -> portId list
val next_hop : t -> V.t -> portId -> V.t

  (* Utility functions *)
val spanningtree : t -> G.t
val shortest_path : t -> V.t -> V.t -> E.t list
(* val shortest_path_v : t -> V.t -> V.t -> V.t list *)
val stitch : E.t list -> (portId option * V.t * portId option) list
val floyd_warshall : t -> ((V.t * V.t) * V.t list) list
val to_dot : t -> string
val to_string : t -> string
val to_mininet : t -> string

  (* Exceptions *)
exception NotFound of string
exception NoPath of string * string
