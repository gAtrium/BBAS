import 'dart:io';

import 'adb_utils.dart';
import 'traverser.dart';
Future<String> PullFromRemoteDevice_Tree(String remotePath, String localPath, Function(String) updateStatus) async{
  Traverser? traverser_remote = await AdbUtils.Traverse_Remote(remotePath);
  if (traverser_remote == null) {
    return "Error while traversing remote directory. ||Er";
  }
  if (!traverser_remote.is_directory) {
    return "Remote path is not a directory. ||Er";
  }
  
  return await pullRemoteSync(remotePath, localPath, updateStatus, traverser_remote);
}

Future<String> pullRemoteSync(String remotePath, String localPath, Function(String) updateStatus, Traverser remote) async {
  //traverse remote path and check if it already exists in local path, if not, pull it
  return pullRemoteSync_internal(remotePath, localPath, updateStatus, remote);
}
String fixPath(String path) {
  String _p = path.replaceAll(RegExp(r'/+'), "/");
  if(_p.contains("//")){
    print("GOD DAMN IT");
  }
  if(Platform.isWindows) _p = _p.replaceAll("/", "\\");
  return _p;
  
}
Future<String> pullRemoteSync_internal(String remotePath, String localPath, Function(String) updateStatus, Traverser remote, {bool fail_fast = false}) async {
  String res = "";
  if (!remote.is_directory) {
    File d_local = File(localPath + remote.filename.replaceAll("\\", ""));
    if (d_local.existsSync()) {
      //check if local file size is smaller than remote file size, if so, pull it
      num localSize = d_local.lengthSync();
      num remoteSize = remote.size;
      if (localSize < remoteSize) {
        updateStatus("Pulling ${remote.filename}");
        String remoteFileName = remote.filename;
        if(remote.malformedChars.isNotEmpty){
          for(int charIndex in remote.malformedChars){
            remoteFileName = remoteFileName.replaceRange(charIndex, charIndex+1, "*"); // replace the character with a wildcard, if it's at the end of the filename, god help us
          }
        }
        res += await AdbUtils.pullFile(remoteFileName, localPath) ? "" : "${remote.filename}\n";
      }
      else {
        updateStatus("Skipping ${remote.filename}");
        //print("Skibbidy ${remote.filename}");
      }
    }
    else {
      updateStatus("Pulling ${remote.filename}");
      String remoteFileName = remote.filename;
        if(remote.malformedChars.isNotEmpty){
          for(int charIndex in remote.malformedChars){
            remoteFileName = remoteFileName.replaceRange(charIndex, charIndex+1, "*"); // replace the character with a wildcard, if it's at the end of the filename, god help us
          }
        }
      res += await AdbUtils.pullFile(remoteFileName, "$localPath/${remote.filename.replaceAll("\\", "")}") ? "" : "${remote.filename}\n";
    }    
  }
  else {
    //check if local directory exists, if not, create it
    //for each child in remote, check if it exists in local, if not, pull it
    String _localpath = fixPath("$localPath${remote.filename.replaceAll("\\", "")}");
    Directory localDir = Directory(_localpath);
    if (!localDir.existsSync()) {
      localDir.createSync(recursive: true);
    }
    if (remote.children.isEmpty) {
      return "";
    }
    for (Traverser child in remote.children) {
      String res_new = await pullRemoteSync_internal("${child.filename}", "${localPath}", updateStatus, child);
      res += "$res_new\n";
  }
  }
  return res.trim();
}