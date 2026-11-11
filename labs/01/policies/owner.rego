package k8sdemorequiredlabels

violation contains {"msg": msg} if {
  labels := object.get(input.review.object.metadata, "labels", {})
  some label in input.parameters.labels
  not label in object.keys(labels)
  msg := sprintf("Missing required label: %v", [label])
}
