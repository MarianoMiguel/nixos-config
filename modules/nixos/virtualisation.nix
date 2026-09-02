{ ... }:

{
  # Rootless Docker: the daemon runs as the user, so the socket is no longer
  # a root-equivalent capability handed to every process running as that
  # user (docker run -v /:/host was a passwordless root shell). Trade-offs:
  # no privileged ports below 1024 without a sysctl, and bind mounts see
  # the user's subordinate uid/gid mapping instead of root's.
  virtualisation.docker.rootless = {
    enable = true;
    # Point the docker CLI and docker-compose at the per-user socket.
    setSocketVariable = true;
  };
}
