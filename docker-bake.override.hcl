variable "REGISTRY" {
  default = "docker.io"
}

# Registry is broken right now wrt gomodules
variable "GO111MODULE" {
  default = "auto"
}
target "default" {
  inherits = ["shared"]
  args = {
    BUILD_TITLE = "Docker Registry"
    BUILD_DESCRIPTION = "A dubo image for Docker registry"
    GO111MODULE = "${GO111MODULE}"
  }
  tags = [
    "${REGISTRY}/dubodubonduponey/registry",
  ]
}
