import 'package:flutter/widgets.dart';

import '../di/container.dart';
import 'lx_scope.dart';

extension LxBuildContextExtension on BuildContext {
  LxContainer get lx => LxScope.of(this);
}
