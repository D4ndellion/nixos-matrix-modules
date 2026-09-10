{ lib }:
rec {
  isSystemdPath = path: path != null && lib.hasPrefix "systemd:" path;
  systemdSocketName = path: lib.removePrefix "systemd:" path;
  systemdSocketPath = socketDir: path: "${socketDir}/${systemdSocketName path}.sock";
  resolveSystemdListeners = socketDir: map (listener:
    if isSystemdPath (listener.path or null)
      then listener // { path = systemdSocketPath socketDir listener.path; }
      else listener);

  # checks if given listener configuration has type as a resource
  isListenerType = type: l: lib.any (r: lib.any (n: n == type) r.names) l.resources;
  # Get the first listener that includes the given resource from worker
  firstListenerOfType = type: ls: lib.lists.findFirst (isListenerType type)
    (throw "No listener with resource: ${type} configured")
    ls;
  # Get an attrset of the host and port from a listener
  connectionInfo = l: {
    host = lib.head l.bind_addresses;
    port = l.port;
  };

  # Get an attrset of the host and port from a worker given a type
  workerConnectionResource = r: w: let
    l = firstListenerOfType r w.settings.worker_listeners;
  in connectionInfo l;

  mapWorkersToUpstreamsByType = workerInstances:
    lib.pipe workerInstances [
      lib.attrValues

      # Index by worker type
      (lib.foldl (acc: worker: acc // {
        ${worker.type} = (acc.${worker.type} or [ ]) ++ [ worker ];
      }) { })

      # Subindex by resource names, listener types, and convert to upstreams
      (lib.mapAttrs (_: workers: lib.pipe workers [
        (lib.concatMap (worker: [ (lib.lists.head  worker.settings.worker_listeners) ]))
        lib.flatten
        mapListenersToUpstreamsByType
      ]))
    ];

    mapListenersToUpstreamsByType = listenerInstances:
      lib.pipe listenerInstances [
        # Index by resource names
        (lib.concatMap (listener: lib.pipe listener [
          (listener: let
            allResourceNames = lib.pipe listener.resources [
              (map (resource: resource.names))
              lib.flatten
              lib.unique
            ];
          in if allResourceNames == [ ]
            then { "empty" = listener; }
            else lib.genAttrs allResourceNames (_: listener))
          lib.attrsToList
        ]))

        (lib.foldl (acc: listener: acc // {
          ${listener.name} = (acc.${listener.name} or [ ]) ++ [ listener.value ];
        }) { })

        # Index by listener type
        (lib.mapAttrs (_:
          (lib.foldl (acc: listener: acc // {
            ${listener.type} = (acc.${listener.type} or [ ]) ++ [ listener ];
          }) { })
        ))

        # Convert listeners to upstream URIs
        (lib.mapAttrs (_:
          (lib.mapAttrs (_: listeners:
            lib.pipe listeners [
              (lib.concatMap (listener:
                if listener.path != null
                  then [ "unix:${listener.path}" ]
                  else (map (addr: "${addr}:${toString listener.port}") listener.bind_addresses)
              ))
              # NOTE: Adding ` = { }` to every upstream might seem unnecessary in isolation,
              #       but it makes it easier to set upstreams in the nginx module.
              (uris: lib.genAttrs uris (_: { }))
            ]
          ))
        ))
      ];
}
