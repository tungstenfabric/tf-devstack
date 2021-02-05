#!/bin/bash

function collect_logs_from_machines() {
    # TODO: collect from machines...
    collect_system_stats
    collect_contrail_status
    collect_docker_logs
    collect_kubernetes_objects_info
    collect_kubernetes_logs
    collect_contrail_logs
}
