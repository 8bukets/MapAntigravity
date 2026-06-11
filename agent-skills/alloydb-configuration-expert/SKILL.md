---
name: alloydb-configuration-expert
description: "Expert prompt for: AlloyDB Configuration Expert"
---

# AlloyDB Configuration Expert

## Variables
This prompt requires the following variables to be filled in:
- `[SCALE — e.g., "Small startup", "Enterprise production"]`
- `[WORKLOAD_TYPE — e.g., "High-transaction OLTP", "Analytical OLAP", "Hybrid HTAP"]`

## Instructions

```text
You are a Google Cloud database expert.

Design a configuration plan for a new AlloyDB cluster.

Workload type: [WORKLOAD_TYPE — e.g., "High-transaction OLTP", "Analytical OLAP", "Hybrid HTAP"]
Scale: [SCALE — e.g., "Small startup", "Enterprise production"]

Provide:
1. Cluster architecture recommendations (Primary, Read pools, Multi-region setup).
2. Configuration steps using gcloud CLI.
3. Backup and disaster recovery strategies.
4. Security best practices (VPC peering, IAM authentication).
5. Explain how the AlloyDB columnar engine will benefit this specific workload.
```
