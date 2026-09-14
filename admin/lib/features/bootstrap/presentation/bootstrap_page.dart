import 'package:flutter/material.dart';

import '../../../shared/presentation/page_help_button.dart';

class BootstrapPage extends StatelessWidget {
  const BootstrapPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: const [
        PageHelpButton(
          englishTitle: 'Getting started',
          chineseTitle: '开始使用',
          englishBody:
              'Sign in to select a workspace, create a site and install its tracker before analytics data can appear.',
          chineseBody: '请先登录并选择工作区，创建站点并安装追踪器，之后分析数据才会出现。',
        ),
      ],
    ),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'SeeRay Lens',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text('Admin foundation is ready.'),
        ],
      ),
    ),
  );
}
