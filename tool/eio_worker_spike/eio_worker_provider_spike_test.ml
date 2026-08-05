module Provider = Eio_worker_provider_spike

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel))
;;

let write_file path contents =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out channel)
    (fun () -> output_string channel contents)
;;

let verify_payload contents =
  String.iteri
    (fun index byte ->
       let expected = index mod 251 in
       let actual = Char.code byte in
       if actual <> expected
       then fail "payload byte %d is %d, expected %d" index actual expected)
    contents
;;

let () =
  if Array.length Sys.argv <> 2
  then fail "usage: eio_worker_provider_spike_test.exe <confined-directory>";
  let directory = Sys.argv.(1) in
  let outside_sentinel =
    Filename.concat (Filename.dirname directory) "outside-sentinel"
  in
  write_file outside_sentinel "outside-must-remain-unchanged";
  let domain0 = Domain.self () in
  let payload_bytes = (2 * Provider.chunk_size) + 17 in
  let report = Provider.run ~directory ~payload_bytes in
  require
    (report.worker_domain_id <> domain0)
    "provider spike ran on domain 0 instead of a spawned Worker Domain";
  require report.timer_peer_ran "timer sleep blocked another runnable fiber";
  require
    (report.timer_elapsed_seconds >= 0.005)
    "Eio timer returned before the requested delay";
  require
    (report.timer_elapsed_seconds < 1.0)
    "Eio timer exceeded the bounded test duration";
  require
    (report.socketpair_payload = "socketpair-ready")
    "socketpair did not transfer the expected payload";
  require
    (report.file_bytes = payload_bytes)
    "chunked file read returned the wrong byte count";
  require
    (report.write_chunks = 3)
    "chunked file write did not include the partial final chunk";
  require
    report.atomic_replace_removed_stale_contents
    "atomic rename did not replace the stale destination";
  require report.directory_escape_rejected "confined directory allowed parent traversal";
  let final_path = Filename.concat directory Provider.final_name in
  let contents = read_file final_path in
  require (String.length contents = payload_bytes) "final demo file has the wrong size";
  verify_payload contents;
  require
    (read_file outside_sentinel = "outside-must-remain-unchanged")
    "confined file operations modified the outside sentinel";
  require (report.dns_address_count > 0) "localhost DNS lookup returned no addresses";
  require
    (report.tcp_payload = "tcp-loopback-ready")
    "loopback TCP request did not return the expected payload";
  require report.waiting_socket_cancelled "waiting socket request was not cancelled";
  require report.waiting_socket_closed "cancelled waiting socket remained open";
  require
    (report.after_cancellation_payload = "session-still-usable")
    "session could not perform socket I/O after request cancellation";
  print_endline "Eio Worker macOS provider Phase 0 spike tests passed"
;;
