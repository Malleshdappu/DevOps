#!/bin/bash

OUTPUT_FILE="k8s_final_inventory.csv"

echo "--------------------------------------------------"
echo " Starting K8s Inventory Report Generation"
echo "--------------------------------------------------"

# 1. Get Cluster Name and data
CLUSTER_NAME=$(kubectl config current-context)
DATA=$(kubectl get pods,deploy,sts --all-namespaces -o json)
NAMESPACES=$(echo "$DATA" | jq -r '.items[].metadata.namespace' | sort -u)

# 2. Process data
echo "$DATA" | jq -r --arg sq "'" --arg cluster "$CLUSTER_NAME" '
  # Helper functions for CPU/Memory unit conversion
  def to_m(val): if val == null or val == "" or val == "0" then 0 elif (val | endswith("m")) then (val | rtrimstr("m") | tonumber) else (val | tonumber * 1000) end;
  def to_mi(val): if val == null or val == "" or val == "0" then 0 elif (val | endswith("Gi")) then (val | rtrimstr("Gi") | tonumber * 1024) elif (val | endswith("Mi")) then (val | rtrimstr("Mi") | tonumber) else (val | tonumber / 1024 / 1024) end;

  # Create lookup map for replicas
  (reduce (.items[] | select(.kind == "Deployment" or .kind == "StatefulSet")) as $item ({};
    .["\($item.metadata.namespace)|\($item.metadata.name)"] = $item.spec.replicas
  )) as $replicas_map |

  # Calculate Total Replicas sum for the top cell
  ( [ .items[] | select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.replicas ] | add // 0 ) as $total_replicas_sum |

  # Calculate Cluster-wide Totals
  ( [ .items[] | select(.kind == "Pod") | .spec.containers[] ] | {
      cpu_req: (map(to_m(.resources.requests.cpu)) | add),
      mem_req: (map(to_mi(.resources.requests.memory)) | add),
      cpu_lim: (map(to_m(.resources.limits.cpu)) | add),
      mem_lim: (map(to_mi(.resources.limits.memory)) | add)
  }) as $total |

  # --- CSV OUTPUT ---

  # Row 1: Cluster Name, Resource Totals, and Total Replicas in the 9th cell
  ["CLUSTER:", $cluster, "TOTAL:", ($total.cpu_req | tostring + "m"), ($total.mem_req | tostring + "Mi"), ($total.cpu_lim | tostring + "m"), ($total.mem_lim | tostring + "Mi"), "", ($total_replicas_sum | tostring)],

  # Row 2: Headers
  ["NAMESPACE", "POD", "CONTAINER", "CPU_REQ", "MEM_REQ", "CPU_LIM", "MEM_LIM", "JAVA_OPTS", "DESIRED_REPLICAS"],

  # Row 3+: Data processing
  (
    [.items[] | select(.kind == "Pod")] |
    group_by(.metadata.namespace + (if .metadata.ownerReferences[0].kind == "ReplicaSet" then (.metadata.ownerReferences[0].name | split("-") | .[:-1] | join("-")) else (.metadata.ownerReferences[0].name // "none") end)) |
    .[] |
    . as $pod_group |
    range(length) as $pod_idx |
    $pod_group[$pod_idx] as $pod |
    $pod.metadata.namespace as $ns |

    $pod.spec.containers[] | . as $container |

    (if $pod.metadata.ownerReferences[0].kind == "ReplicaSet" then ($pod.metadata.ownerReferences[0].name | split("-") | .[:-1] | join("-")) else ($pod.metadata.ownerReferences[0].name // "none") end) as $pname |

    # Replica logic: Show only once per group
    (if $pod_idx == 0 and $container.name != "istio-proxy" then
        ($replicas_map["\($ns)|\($pname)"] | tostring)
     else "" end) as $replica_display |

    [
      $ns,
      $pod.metadata.name,
      $container.name,
      (if .resources.requests.cpu == "0" or .resources.requests.cpu == null then "" else .resources.requests.cpu end),
      (if .resources.requests.memory == "0" or .resources.requests.memory == null then "" else .resources.requests.memory end),
      (if .resources.limits.cpu == "0" or .resources.limits.cpu == null then "" else .resources.limits.cpu end),
      (if .resources.limits.memory == "0" or .resources.limits.memory == null then "" else .resources.limits.memory end),
      (if $container.name == "istio-proxy" then "" else
        (((($container.env // []) | map(select(.name | test("JAVA_OPT|JDK_JAVA_OPTIONS"))) | .[0].value) // "") | if . != "" then ($sq + .) else "" end)
      end),
      $replica_display
    ]
  ) | @csv
' > "$OUTPUT_FILE"

# 3. Progress Feedback
for ns in $NAMESPACES; do
    echo "Successfully processed Namespace: [$ns] ✓"
done

echo "--------------------------------------------------"
echo " SUCCESS: Generated $OUTPUT_FILE for cluster [$CLUSTER_NAME]"
echo "--------------------------------------------------"
