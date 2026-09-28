import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/gist_backup/gist_backup_controller.dart';

class GistBackupBinding extends Binding {
  @override
  List<Bind> dependencies() {
    return [Bind.lazyPut(() => GistBackupController())];
  }
}
