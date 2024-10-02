import 'dart:io';

class Traverser {
  String filename;
  bool is_directory;
  num size;
  List<Traverser> children ;
  Traverser(this.filename, this.is_directory, {this.children = const [], this.size = 0});
}

Traverser traverseDirectory(String path) {
  Directory directory = Directory(path);
  List<Traverser> children = [];

  if (directory.existsSync()) {
    List<FileSystemEntity> entities = directory.listSync();

    for (FileSystemEntity entity in entities) {
      String filename = entity.path.split('/').last;
      bool isDirectory = entity is Directory;

      if (isDirectory) {
        children.add(traverseDirectory(entity.path));
      } else {
        children.add(Traverser(filename, false));
      }
    }
  }

  return Traverser(directory.path, true, children: children);
}
num totalFilesInTraverser(Traverser traverser) {
  num total = 0;
  for (Traverser child in traverser.children) {
    if (child.is_directory) {
      total += totalFilesInTraverser(child);
    } else {
      total += 1;
    }
  }
  return total;
}