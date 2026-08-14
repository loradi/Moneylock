import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import 'insights_agent.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
              largeTitle: Text('Insights')),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Generated from your spending this month.',
                style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel),
              ),
            ),
          ),
          insights.when(
            data: (capsules) => SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _CapsuleCard(capsules[i]),
                childCount: capsules.length,
              ),
            ),
            loading: () => const SliverToBoxAdapter(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CupertinoActivityIndicator()))),
            error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Could not load insights: $e')))),
          ),
        ],
      ),
    );
  }
}

class _CapsuleCard extends StatelessWidget {
  final InsightCapsule capsule;
  const _CapsuleCard(this.capsule);

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CupertinoColors.systemBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: CupertinoColors.separator),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(capsule.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(capsule.body,
                  style: const TextStyle(
                      fontSize: 14, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}