open Core

(*===========================================================================*)
(* UTILITY FUNCTIONS                                                         *)
(*===========================================================================*)

let parse_pol ?(json=false) file =
  match json with
  | false -> Frenetic_NetKAT_Parser.pol_of_file file
  | true ->
    In_channel.create file
    |> Frenetic_NetKAT_Json.pol_of_json_channel

let parse_pred file = Frenetic_NetKAT_Parser.pred_of_file file

let fmt = Format.formatter_of_out_channel stdout
let _ = Format.pp_set_margin fmt 120

let print_fdd fdd =
  printf "%s\n" (Frenetic_NetKAT_Compiler.to_string fdd)

let dump data ~file =
  Out_channel.write_all file ~data

let dump_fdd fdd ~file =
  dump ~file (Frenetic_NetKAT_Compiler.to_dot fdd)

let dump_auto auto ~file =
  dump ~file (Frenetic_NetKAT_Compiler.Automaton.to_dot auto)

let print_table fdd sw =
  Frenetic_NetKAT_Compiler.to_table sw fdd
  |> Frenetic_OpenFlow.string_of_flowTable ~label:(sprintf "Switch %Ld" sw)
  |> printf "%s\n"

let print_all_tables ?(no_tables=false) fdd switches =
  if not no_tables then List.iter switches ~f:(print_table fdd)

let time f =
  let t1 = Unix.gettimeofday () in
  let r = f () in
  let t2 = Unix.gettimeofday () in
  (t2 -. t1, r)

let print_time ?(prefix="") time =
  printf "%stime: %.4f\n" prefix time

let print_order () =
  Frenetic_NetKAT_Compiler.Field.(get_order ()
    |> List.map ~f:to_string
    |> String.concat ~sep:" > "
    |> printf "FDD field ordering: %s\n")


(*===========================================================================*)
(* FLAGS                                                                     *)
(*===========================================================================*)

module Flag = struct
  open Command.Spec

  let switches =
    flag "--switches" (optional int)
      ~doc:"n number of switches to dump flow tables for (assuming \
            switch-numbering 1,2,...,n)"

  let print_fdd =
    flag "--print-fdd" no_arg
      ~doc:" print an ASCI encoding of the intermediate representation (FDD) \
            generated by the local compiler"

  let dump_fdd =
    flag "--dump-fdd" no_arg
      ~doc:" dump a dot file encoding of the intermediate representation \
            (FDD) generated by the local compiler"

  let print_auto =
    flag "--print-auto" no_arg
      ~doc:" print an ASCI encoding of the intermediate representation \
            generated by the global compiler (symbolic NetKAT automaton)"

  let dump_auto =
    flag "--dump-auto" no_arg
      ~doc:" dump a dot file encoding of the intermediate representation \
            generated by the global compiler (symbolic NetKAT automaton)"

  let print_global_pol =
    flag "--print-global-pol" no_arg
      ~doc: " print global NetKAT policy generated by the virtual compiler"

  let no_tables =
    flag "--no-tables" no_arg
      ~doc: " Do not print tables."

  let json =
    flag "--json" no_arg
      ~doc: " Parse input file as JSON."

  let print_order =
    flag "--print-order" no_arg
      ~doc: " Print FDD field order used by the compiler."

  let vpol =
    flag "--vpol" (optional_with_default "vpol.dot" file)
      ~doc: "file Virtual policy. Must not contain links. \
             If not specified, defaults to vpol.dot"

  let vrel =
    flag "--vrel" (optional_with_default "vrel.kat" file)
      ~doc: "file Virtual-physical relation. If not specified, defaults to vrel.kat"

  let vtopo =
    flag "--vtopo" (optional_with_default "vtopo.kat" file)
      ~doc: "file Virtual topology. If not specified, defaults to vtopo.kat"

  let ving_pol =
    flag "--ving-pol" (optional_with_default "ving_pol.kat" file)
      ~doc: "file Virtual ingress policy. If not specified, defaults to ving_pol.kat"

  let ving =
    flag "--ving" (optional_with_default "ving.kat" file)
      ~doc: "file Virtual ingress predicate. If not specified, defaults to ving.kat"

  let veg =
    flag "--veg" (optional_with_default "veg.kat" file)
      ~doc: "file Virtual egress predicate. If not specified, defaults to veg.kat"

  let ptopo =
    flag "--ptopo" (optional_with_default "ptopo.kat" file)
      ~doc: "file Physical topology. If not specified, defaults to ptopo.kat"

  let ping =
    flag "--ping" (optional_with_default "ping.kat" file)
      ~doc: "file Physical ingress predicate. If not specified, defaults to ping.kat"

  let peg =
    flag "--peg" (optional_with_default "peg.kat" file)
      ~doc: "file Physical egress predicate. If not specified, defaults to peg.kat"

  let determinize =
    flag "--determinize" no_arg
      ~doc:"Determinize automaton."

  let minimize =
    flag "--minimize" no_arg
      ~doc:"Minimize automaton (heuristically)."
end


(*===========================================================================*)
(* COMMANDS: Local, Global, Virtual, Auto, Decision                          *)
(*===========================================================================*)

module Local = struct
  let spec = Command.Spec.(
    empty
    +> anon ("file" %: file)
    +> Flag.switches
    +> Flag.print_fdd
    +> Flag.dump_fdd
    +> Flag.no_tables
    +> Flag.json
    +> Flag.print_order
  )

  let run file nr_switches printfdd dumpfdd no_tables json printorder () =
    let pol = parse_pol ~json file in
    let (t, fdd) = time (fun () -> Frenetic_NetKAT_Compiler.compile_local pol) in
    let switches = match nr_switches with
      | None -> Frenetic_NetKAT_Semantics.switches_of_policy pol
      | Some n -> List.range 0 n |> List.map ~f:Int64.of_int
    in
    if Option.is_none nr_switches && List.is_empty switches then
      printf "Number of switches not automatically recognized!\n\
              Use the --switch flag to specify it manually.\n"
    else
      if printorder then print_order ();
      if printfdd then print_fdd fdd;
      if dumpfdd then dump_fdd fdd ~file:(file ^ ".dot");
      print_all_tables ~no_tables fdd switches;
      print_time ~prefix:"compilation " t;
end



module Global = struct
  let spec = Command.Spec.(
    empty
    +> anon ("file" %: file)
    +> Flag.print_fdd
    +> Flag.dump_fdd
    +> Flag.print_auto
    +> Flag.dump_auto
    +> Flag.no_tables
    +> Flag.json
    +> Flag.print_order
  )

  let run file printfdd dumpfdd printauto dumpauto no_tables json printorder () =
    let pol = parse_pol ~json file in
    let (t, fdd) = time (fun () -> Frenetic_NetKAT_Compiler.compile_global pol) in
    let switches = Frenetic_NetKAT_Semantics.switches_of_policy pol in
    if printorder then print_order ();
    if printfdd then print_fdd fdd;
    if dumpfdd then dump_fdd fdd ~file:(file ^ ".dot");
    print_all_tables ~no_tables fdd switches;
    print_time ~prefix:"compilation " t;

end



module Virtual = struct
  let spec = Command.Spec.(
    empty
    +> anon ("file" %: file)
    +> Flag.vrel
    +> Flag.vtopo
    +> Flag.ving_pol
    +> Flag.ving
    +> Flag.veg
    +> Flag.ptopo
    +> Flag.ping
    +> Flag.peg
    +> Flag.print_fdd
    +> Flag.dump_fdd
    +> Flag.print_global_pol
    +> Flag.no_tables
    +> Flag.print_order
  )

  let run vpol_file vrel vtopo ving_pol ving veg ptopo ping peg printfdd dumpfdd printglobal
    no_tables printorder () =
    (* parse files *)
    let vpol = parse_pol vpol_file in
    let vrel = parse_pred vrel in
    let vtopo = parse_pol vtopo in
    let ving_pol = parse_pol ving_pol in
    let ving = parse_pred ving in
    let veg = parse_pred veg in
    let ptopo = parse_pol ptopo in
    let ping = parse_pred ping in
    let peg = parse_pred peg in

    (* compile *)
    let module FG = Frenetic_NetKAT_FabricGen.FabricGen in
    let module Virtual = Frenetic_NetKAT_Virtual_Compiler.Make(FG) in
    let (t1, global_pol) = time (fun () ->
      Virtual.compile vpol ~log:true ~vrel ~vtopo ~ving_pol ~ving ~veg ~ptopo ~ping ~peg) in
    let (t2, fdd) = time (fun () -> Frenetic_NetKAT_Compiler.compile_global global_pol) in

    (* print & dump *)
    let switches = Frenetic_NetKAT_Semantics.switches_of_policy global_pol in
    if printglobal then begin
      Format.fprintf fmt "Global Policy:@\n@[%a@]@\n@\n"
        Frenetic_NetKAT_Pretty.format_policy global_pol
    end;
    if printorder then print_order ();
    if printfdd then print_fdd fdd;
    if dumpfdd then dump_fdd fdd ~file:(vpol_file ^ ".dot");
    print_all_tables ~no_tables fdd switches;
    print_time ~prefix:"virtual compilation " t1;
    print_time ~prefix:"global compilation " t2;
end


module Auto = struct
  let spec = Command.Spec.(
    empty
    +> anon ("file" %: file)
    +> Flag.json
    +> Flag.print_order
    +> Flag.determinize
    +> Flag.minimize
  )

  let run file json printorder dedup cheap_minimize () =
    let pol = parse_pol ~json file in
    let (t, auto) = time (fun () ->
      Frenetic_NetKAT_Compiler.Automaton.of_pol pol ~dedup ~cheap_minimize) in
    if printorder then print_order ();
    dump_auto auto ~file:(file ^ ".auto.dot");
    print_time t;

end

module Decision = struct
  let spec = Command.Spec.(
    empty
    +> anon ("file-1" %: file)
    +> anon ("file-2" %: file)
    +> Flag.dump_auto
    +> Flag.json
    +> Flag.print_order
  )

  let run file1 file2 dumpauto json printorder () =
    let pol1 = parse_pol ~json file1 in
    let pol2 = parse_pol ~json file2 in
    let (a1, a2) = Frenetic_NetKAT_Compiler.Automaton.(of_pol pol1, of_pol pol2) in
    if printorder then print_order ();
    if dumpauto then dump_auto a1 ~file:(file1 ^ ".auto.dot");
    if dumpauto then dump_auto a2 ~file:(file2 ^ ".auto.dot");
    let module Hopcroft = Frenetic_NetKAT_Equivalence.Hopcroft in
    let module Simple = Frenetic_NetKAT_Equivalence.Simple in
    let (th, h) = time (fun () -> Hopcroft.equiv a1 a2) in
    let (ts, s) = time (fun () -> Simple.equiv a1 a2) in
    printf "equivalent (Hopcroft): %s\n" (Bool.to_string h);
    print_time th;
    printf "\nequivalent (Simple): %s\n" (Bool.to_string s);
    print_time ts

end



(*===========================================================================*)
(* BASIC SPECIFICATION OF COMMANDS                                           *)
(*===========================================================================*)

let local : Command.t =
  Command.basic
    ~summary:"Runs local compiler and dumps resulting tables."
    (* ~readme: *)
    Local.spec
    Local.run

let global : Command.t =
  Command.basic
    ~summary:"Runs global compiler and dumps resulting tables."
    (* ~readme: *)
    Global.spec
    Global.run

let virt : Command.t =
  Command.basic
    ~summary:"Runs virtual compiler and dumps resulting tables."
    (* ~readme: *)
    Virtual.spec
    Virtual.run

let auto : Command.t =
  Command.basic
    ~summary:"Converts program to automaton and dumps it."
    (* ~readme: *)
    Auto.spec
    Auto.run

let decision : Command.t =
  Command.basic
    ~summary:"Decides program equivalence."
    (* ~readme: *)
    Decision.spec
    Decision.run

let main : Command.t =
  Command.group
    ~summary:"Runs (local/global/virtual) compiler and dumps resulting tables."
    (* ~readme: *)
    [("local", local); ("global", global); ("virtual", virt); ("auto", auto);
     ("decision", decision)]
