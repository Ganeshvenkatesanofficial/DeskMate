import 'package:deskmate_app/app/backend_manager.dart';
import 'package:deskmate_app/app/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = {'status': 'ok', 'local_llm': 'offline', 'app_version': '2.0.0'};

  test('an engine serving this app\'s Folder Agent API is compatible', () {
    expect(BackendManager.engineFit({...base, 'folder_agent_api': AppConstants.folderAgentApi}), EngineFit.compatible);
  });

  test('an older DeskMate engine (no Folder Agent API) is outdated, never adopted', () {
    expect(BackendManager.engineFit({...base, 'meeting_ready': true}), EngineFit.outdated);
    expect(BackendManager.engineFit({...base, 'folder_agent_api': 0}), EngineFit.outdated);
  });

  test('anything else answering /api/health is ignored', () {
    expect(BackendManager.engineFit({'status': 'ok'}), EngineFit.none);
    expect(BackendManager.engineFit('ok'), EngineFit.none);
  });
}
