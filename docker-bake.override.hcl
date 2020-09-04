target "default" {
  inherits = ["shared"]
  args = {
    BUILD_TITLE = "Docker Registry"
    BUILD_DESCRIPTION = "A dubo image for Docker registry"
  }
  tags = [
    "dubodubonduponey/registry",
  ]
}
