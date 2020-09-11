package bake

command: {
  image: #Dubo & {
    target: ""
    args: {
      BUILD_TITLE: "Registry"
      BUILD_DESCRIPTION: "A dubo image for Registry based on \(args.DEBOOTSTRAP_SUITE) (\(args.DEBOOTSTRAP_DATE))"
    }
  }
}
