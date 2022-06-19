job "payments-deployment" {
  type = "service"

  datacenters = ["dc1"]

  group "payments" {
    count = 3

    network {
      mode = "bridge"
      port "http" {
        to = "3000"
      }

      # dynamic port for the metrics
      port "metrics" {
        to = "9102"
      }
    }

    # create a service so that promethues can scrape the metrics
    service {
      name = "payments-metrics"
      port = "metrics"
      tags = ["metrics"]
      meta {
        metrics    = "prometheus"
        job        = "$${NOMAD_JOB_NAME}"
        datacenter = "$${node.datacenter}"
      }
    }

    service {
      name = "payments"
      port = "3000"

      connect {
        sidecar_service {
          proxy {
            # expose the metrics endpont 
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }

            upstreams {
              destination_name = "payments-db"
              local_bind_port  = 5432
            }
          }
        }
      }
    }

    task "payments" {
      driver = "docker"

      config {
        image = "${artifact.image}:${artifact.tag}"
        ports = ["http"]
      }

      env {
        NAME                 = "PAYMENTS V1"
        TIMING_50_PERCENTILE = "20ms"
      }
    }

    # envoy is bound to ip 127.0.0.2 however expose only accepts redirects to 127.0.0.1
    # run socat to redirect the envoy admin port to localhost
    task "socat" {
      driver = "docker"

      config {
        image = "alpine/socat"
        args = [
          "TCP-LISTEN:19002,fork,bind=127.0.0.1",
          "TCP:127.0.0.2:19002",
        ]
      }
    }
  }
}
