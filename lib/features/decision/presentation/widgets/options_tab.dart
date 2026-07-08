import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/limits.dart';
import '../../../../core/theme/tokens.dart';
import '../../domain/entities/decision.dart';
import '../providers/decision_editor.dart';

class OptionsTab extends ConsumerWidget {
  const OptionsTab({super.key, required this.decisionId});
  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decision = ref.watch(decisionEditorProvider(decisionId)).value;
    if (decision == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(AppTokens.s4),
      children: [
        for (final option in decision.options)
          _OptionCard(decisionId: decisionId, option: option),
        const SizedBox(height: AppTokens.s2),
        if (decision.options.length < Limits.maxOptions)
          OutlinedButton.icon(
            onPressed: () => _showAddOptionDialog(context, ref),
            icon: const Icon(Icons.add),
            label: Text(
              decision.options.isEmpty
                  ? 'İlk seçeneği ekle'
                  : 'Seçenek ekle (${decision.options.length}/${Limits.maxOptions})',
            ),
          )
        else
          Text(
            'En fazla ${Limits.maxOptions} seçenek eklenebilir.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 96), // bottom bar payı
      ],
    );
  }

  Future<void> _showAddOptionDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni Seçenek'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Örn. iPhone 16'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty) return;
    final failure = await ref
        .read(decisionEditorProvider(decisionId).notifier)
        .addOption(title);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _OptionCard extends ConsumerWidget {
  const _OptionCard({required this.decisionId, required this.option});
  final String decisionId;
  final Option option;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(decisionEditorProvider(decisionId).notifier);

    return Card(
      margin: const EdgeInsets.only(bottom: AppTokens.s3),
      child: ExpansionTile(
        title: Text(option.title),
        subtitle: Text(
          '${option.pros.length} artı · ${option.cons.length} eksi',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Seçeneği sil',
          onPressed: () => notifier.removeOption(option.id),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppTokens.s4,
          0,
          AppTokens.s4,
          AppTokens.s4,
        ),
        children: [
          _ProConList(
            label: 'Artılar',
            icon: Icons.add_circle_outline,
            color: Colors.green,
            items: option.pros,
            onAdd: (text) => notifier.addProCon(option.id, text, isPro: true),
            onRemove: (i) => notifier.removeProCon(option.id, i, isPro: true),
          ),
          const SizedBox(height: AppTokens.s3),
          _ProConList(
            label: 'Eksiler',
            icon: Icons.remove_circle_outline,
            color: Colors.red,
            items: option.cons,
            onAdd: (text) => notifier.addProCon(option.id, text, isPro: false),
            onRemove: (i) => notifier.removeProCon(option.id, i, isPro: false),
          ),
        ],
      ),
    );
  }
}

class _ProConList extends StatefulWidget {
  const _ProConList({
    required this.label,
    required this.icon,
    required this.color,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  final String label;
  final IconData icon;
  final Color color;
  final List<String> items;
  final Future<Object?> Function(String) onAdd;
  final void Function(int) onRemove;

  @override
  State<_ProConList> createState() => _ProConListState();
}

class _ProConListState extends State<_ProConList> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_controller.text.trim().isEmpty) return;
    await widget.onAdd(_controller.text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        for (final (i, item) in widget.items.indexed)
          Row(
            children: [
              Icon(widget.icon, size: 16, color: widget.color),
              const SizedBox(width: AppTokens.s2),
              Expanded(child: Text(item)),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: () => widget.onRemove(i),
              ),
            ],
          ),
        TextField(
          controller: _controller,
          maxLength: 140,
          decoration: InputDecoration(
            hintText: '${widget.label} ekle…',
            counterText: '',
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: _add,
            ),
          ),
          onSubmitted: (_) => _add(),
        ),
      ],
    );
  }
}
