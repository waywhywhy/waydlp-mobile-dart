import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../services/downloads.dart';
import '../services/progress.dart';
import '../theme.dart';
import '../widgets/common.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final d = s.downloads;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) => CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Queue'),
            actions: [
              if (d.jobs.any((j) => j.state.isFinished))
                TextButton(onPressed: d.clearFinished, child: const Text('Clear finished')),
              if (d.jobs.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'More actions',
                  onSelected: (v) => unawaited(switch (v) {
                    'pause' => d.pauseAll(),
                    'resume' => d.resumeAll(),
                    _ => d.retryFailed(),
                  }),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'pause',
                      enabled: d.jobs.any((j) => j.state.isActive),
                      child: const Text('Pause all'),
                    ),
                    PopupMenuItem(
                      value: 'resume',
                      enabled: d.jobs.any((j) => j.state == JobState.paused),
                      child: const Text('Resume all'),
                    ),
                    PopupMenuItem(
                      value: 'retry',
                      enabled: d.jobs.any((j) => j.state == JobState.failed),
                      child: Text('Retry failed (${d.jobs.where((j) => j.state == JobState.failed).length})'),
                    ),
                  ],
                ),
            ],
          ),
          if (d.jobs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.download_outlined,
                title: 'Nothing in the queue',
                hint: 'Analyze a link or share one to waydlp.',
              ),
            )
          else
            SliverList.separated(
              itemCount: d.jobs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (c, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _JobCard(job: d.jobs[i], reduceMotion: s.settings.value.reduceMotion),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.reduceMotion});
  final Job job;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final d = s.downloads;
    final p = job.progress;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill(job.state.label, color: stateColor(job.state)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  job.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${job.options.summary}${job.isPlaylist ? ' · playlist' : ''}${job.attempts > 1 ? ' · attempt ${job.attempts}' : ''}',
            style: const TextStyle(color: Palette.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (job.state == JobState.running)
            JobProgress(
              fraction: p?.fraction,
              text: p == null ? job.stage : '${job.stage} · ${progressText(p)}',
              animate: !reduceMotion,
            )
          else if (job.state == JobState.paused)
            JobProgress(fraction: p?.fraction ?? 0, text: job.stage, animate: false)
          else if (job.state == JobState.failed || job.state == JobState.waitingRetry)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (job.state == JobState.waitingRetry) Text(job.stage, style: const TextStyle(color: Palette.text2)),
                if (job.failure != null) FailureView(job.failure!),
              ],
            )
          else
            Text(job.stage, style: TextStyle(color: job.state == JobState.completed ? Palette.success : Palette.text2)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              if (job.state == JobState.running || job.state == JobState.queued) ...[
                OutlinedButton.icon(
                  onPressed: () => unawaited(d.pause(job)),
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(d.cancel(job)),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
              ],
              if (job.state == JobState.paused) ...[
                FilledButton.icon(
                  onPressed: () => unawaited(d.resume(job)),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(d.cancel(job)),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
              ],
              // Previously a job waiting for an automatic retry had no buttons at all.
              if (job.state == JobState.waitingRetry) ...[
                FilledButton.icon(
                  onPressed: () => unawaited(d.resume(job)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry now'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(d.cancel(job)),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
              ],
              if (job.state == JobState.failed || job.state == JobState.cancelled)
                FilledButton.icon(
                  onPressed: () => unawaited(d.resume(job)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              if (job.state == JobState.completed && job.savedUris.isNotEmpty) ...[
                FilledButton.icon(
                  onPressed: () => unawaited(s.engine.openUri(job.savedUris.first, job.mime ?? '*/*')),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Open'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(s.engine.shareUri(job.savedUris.first, job.mime ?? '*/*')),
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
              ],
              if (job.state.isFinished)
                IconButton(
                  tooltip: 'Remove from queue',
                  onPressed: () => d.remove(job),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
