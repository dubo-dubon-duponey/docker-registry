target "default" {
  inherits = ["shared"]
  args = {
    BUILD_TITLE = "Docker Registry"
    BUILD_DESCRIPTION = "A dubo image for Docker registry"
  }
  tags = [
    "dubodubonduponey/registry",
  ]
  platforms = [
    "linux/amd64",
    "linux/arm64",
    "linux/arm/v7",
    "linux/arm/v6",
    "linux/386",
    "linux/s390x",
    "linux/ppc64el",
  ]
}
