let () =
  Native_backend.embed ~name:"host_navigation" (App.create Host_navigation.component)
;;
