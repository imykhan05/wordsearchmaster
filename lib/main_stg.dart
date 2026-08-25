import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/config/app_config.dart';

Future<void> main() async {
  await bootstrap(AppConfig.stg(), () => const WordSearchMasterApp());
}
