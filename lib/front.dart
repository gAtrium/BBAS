import 'package:betterbetteradbsync/adb_utils.dart';
import 'package:betterbetteradbsync/betterbetteradbsync.dart';
import 'package:betterbetteradbsync/traverser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class BBAS_front extends StatefulWidget {
  const BBAS_front({super.key});

  @override
  State<BBAS_front> createState() => _BBAS_frontState();
}

class _BBAS_frontState extends State<BBAS_front> with TickerProviderStateMixin {
  double icon_size = 200;
  Duration rotateDuration = const Duration(milliseconds: 500);
  bool shouldPull = true;
  bool rotateAllowed = true;
  String currentStatus = "Idle";
  bool Syncing = false;
  bool shouldDisplayIndefinite = false;
  bool hasError = false;
  String local_path = "";
  String remote_path = "";
  double percentage = 0;

  Traverser? traverser_remote;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text("Better Better ADB Sync", style: TextStyle(fontSize: 32)),
          const Text("Because we need more tools, not fixes.",
              style: TextStyle(fontSize: 12)),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 800, minWidth: 500),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.transparent, width: 0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                Icon(Icons.computer_rounded, size: icon_size),
                                Container(
                                  width: icon_size,
                                  height: icon_size-20,
                                  child: Center(
                                    child: Text(
                                      percentage == 0 ? "" : percentage.toStringAsFixed(2) + "%",
                                      style: TextStyle(
                                          fontSize: 24,
                                          color: Colors.black),
                                    ),
                                  ),
                                )
                              ],
                            ),
                            const Text("Computer",
                                style: TextStyle(fontSize: 24)),
                            const Text("This is your computer,",
                                style: TextStyle(fontSize: 10))
                          ],
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black54, width: 2),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: InkWell(
                        onTap: rotateAllowed
                            ? () {
                                setState(() {
                                  if (shouldPull) shouldPull = !shouldPull;
                                });
                              }
                            : null,
                        customBorder: const CircleBorder(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          transform: Matrix4.rotationZ(shouldPull ? 3.14 : 0),
                          alignment: Alignment.center,
                          curve: Curves.elasticInOut,
                          transformAlignment: Alignment.center,
                          child: const Center(
                            child: Icon(Icons.arrow_forward_rounded, size: 100),
                          ),
                          onEnd: () {
                            setState(
                              () {
                                if (!shouldPull) {
                                  shouldPull = !shouldPull;
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.transparent, width: 0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                Icon(Icons.phone_android_rounded,
                                    size: icon_size)
                              ],
                            ),
                            ElevatedButton(
                                onPressed: () async {
                                  setState(() {
                                    shouldDisplayIndefinite = true;
                                    currentStatus = "Querying devices...";
                                  });
                                  await AdbUtils.queryDevices();
                                  if (AdbUtils.Devices.isEmpty) {
                                    setState(() {
                                      currentStatus =
                                          "No devices found. Please connect your phone.";
                                    });
                                    return;
                                  }
                                  List<String> deviceNames =
                                      await AdbUtils.queryDeviceNames();
                                  await showDialog(
                                      context: context,
                                      builder: (context) => SimpleDialog(
                                            title: const Text("Choose Device"),
                                            children: deviceNames
                                                .map((e) => SimpleDialogOption(
                                                      onPressed: () {
                                                        setState(() {
                                                          AdbUtils
                                                              .setChosenDevice(e
                                                                  .split(" ")
                                                                  .first);
                                                        });
                                                        Navigator.pop(context);
                                                      },
                                                      child: Text(e),
                                                    ))
                                                .toList(),
                                          ));
                                  setState(() {
                                    shouldDisplayIndefinite = false;
                                    currentStatus =
                                        "Device chosen: ${AdbUtils.ChosenDevice}";
                                  });
                                },
                                child: Text(AdbUtils.ChosenDevice.isEmpty
                                    ? "Choose Device"
                                    : AdbUtils.ChosenDevice)),
                            Text(
                                AdbUtils.ChosenDevice.isEmpty
                                    ? "This is supposed to be your phone,"
                                    : "This is your phone",
                                style: TextStyle(fontSize: 10))
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          TextButton(
                            onPressed: () async {
                              String? result =
                                  await FilePicker.platform.getDirectoryPath();
                              if (result != null) {
                                setState(() {
                                  local_path = result;
                                });
                              } else {
                                // User canceled the picker
                              }
                            },
                            child: Row(
                              children: [
                                Icon(Icons.folder, size: 30),
                                Text(local_path.isEmpty
                                    ? "Select Folder"
                                    : local_path
                                        .replaceAll('\\', '/')
                                        .split("/")
                                        .last),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(flex: 2, child: Container()),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        decoration: const InputDecoration(
                            labelText: "Remote Path",
                            hintText: "Enter the remote path"),
                        onChanged: (value) {
                          setState(() {
                            remote_path = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Stack(
                  children: [
                    Container(
                      height: 40,
                      child: LinearProgressIndicator(
                        borderRadius: BorderRadius.circular(100),
                        valueColor: hasError
                            ? const AlwaysStoppedAnimation<Color>(Colors.red)
                            : const AlwaysStoppedAnimation<Color>(Colors.blue),
                        value: shouldDisplayIndefinite
                            ? null
                            : percentage == 0
                                ? 0
                                : percentage / 100,
                      ),
                    ),
                    Container(
                      height: 40,
                      child: Center(child: Text(currentStatus)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    if (Syncing) {
                      return;
                    }
                    hasError = false;
                    if (local_path.isEmpty || remote_path.isEmpty) {
                      setState(() {
                        currentStatus = "Please fill all the fields";
                      });
                    } else {
                      setState(() {
                        currentStatus = "Syncing...";
                        Syncing = true;
                        shouldDisplayIndefinite = true;
                        currentStatus = "Traversing remote path...";
                      });
                        bool r_c = await AdbUtils.remoteFolderExists(remote_path);
                        if (!r_c) {
                          setState(() {
                            currentStatus = "Remote path does not exist.";
                            Syncing = false;
                            shouldDisplayIndefinite = false;
                            hasError = true;
                          });
                          return;
                        }
                        setState(() {
                          currentStatus = "Traversing the remote path";
                        });
                        traverser_remote = await AdbUtils.Traverse_Remote(remote_path);
                        if (traverser_remote == null) {
                          setState(() {
                            currentStatus = "Error while traversing remote directory.";
                            Syncing = false;
                            shouldDisplayIndefinite = false;
                            hasError = true;
                          });
                          return;
                        }
                        setState(() {
                          currentStatus = "Traversed!";
                          shouldDisplayIndefinite = false;
                        });
                        if (!traverser_remote!.is_directory) {
                          setState(() {
                            currentStatus = "Remote path is not a directory.";
                            Syncing = false;
                            shouldDisplayIndefinite = false;
                            hasError = true;
                          });
                          return;
                        }
                        num total_files = totalFilesInTraverser(traverser_remote!);
                        num transferred_files = 0;
                        await pullRemoteSync_internal(remote_path, local_path, (String status) {
                          setState(() {
                            currentStatus = status;
                            transferred_files += 1;
                            percentage = (transferred_files / total_files) * 100;
                          });
                        }, traverser_remote!);
                        
                    }
                  },
                  child: Text(Syncing ? "Syncing" : "Sync"),
                ),
                SizedBox(height: 20),
                ElevatedButton(onPressed: traverser_remote != null ? () async{
                  num total_files = totalFilesInTraverser(traverser_remote!);
                        num transferred_files = 0;
                    await pullRemoteSync_internal(remote_path, local_path, (String status) {
                          setState(() {
                            currentStatus = status;
                            transferred_files += 1;
                            percentage = (transferred_files / total_files) * 100;
                          });
                        }, traverser_remote!);
                }: null, child: Text(traverser_remote == null ? "No failed transfer" : "Retry failed transfer")),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
