import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import 'case_workspace.dart';

Future<void> openReference(BuildContext context, String url) async {
  final app = context.read<AppController>();
  try {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('Unavailable');
    }
  } catch (_) {
    if (context.mounted) {
      showMessage(
        context,
        app.tr(
          'Không mở được trình duyệt. Kiểm tra kết nối.',
          'Could not open browser. Check your connection.',
        ),
      );
    }
  }
}

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});
  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool accepted = false;
  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 28),
            Icon(
              Icons.health_and_safety_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text('OrthoAI', style: Theme.of(context).textTheme.headlineLarge),
            Text(
              a.tr(
                'Công cụ dành cho nhân viên y tế',
                'For qualified healthcare professionals',
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            Text(
              a.tr(
                'Bản nghiên cứu / giáo dục 0.1',
                'Research / educational prototype 0.1',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              a.tr(
                'Ứng dụng chưa được thẩm định chẩn đoán hoặc chứng nhận thiết bị y tế. Phân loại do bác sĩ nhập và xác nhận; không có mô hình AI chẩn đoán. Quy tắc AO/OTA 2018 chỉ hỗ trợ nhóm lớn ở người lớn và cần được chuyên gia rà soát.',
                'This application has no diagnostic validation or medical-device certification. Classification is entered and confirmed by a clinician. No diagnostic AI model is installed. AO/OTA 2018 rules cover adult coarse types and require specialist review.',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              a.tr(
                'Dữ liệu ca được mã hóa trong bộ nhớ ứng dụng. Không tự động tải lên mạng. Không nhập danh tính người bệnh. Ảnh có thể chứa tên in trực tiếp: hãy loại bỏ trước khi nhập hoặc chia sẻ. Ảnh chụp phim không tương đương chất lượng phim gốc.',
                'Cases are encrypted in app storage. No automatic uploads. Do not enter patient identifiers. Images may contain burned-in names: remove these before import or sharing. Photographs of films do not equal original radiograph quality.',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              a.tr(
                'Xuất PDF hoặc ảnh sẽ tạo bản sao không mã hóa. Chỉ chia sẻ khi có quyền phù hợp. Xóa ứng dụng có thể làm mất khóa và dữ liệu.',
                'PDF or image export creates an unencrypted copy. Share only with appropriate authorization. Uninstalling may remove keys and data.',
              ),
            ),
            const SizedBox(height: 20),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: accepted,
              title: Text(
                a.tr(
                  'Tôi hiểu giới hạn và đồng ý xử lý dữ liệu cục bộ.',
                  'I understand these limitations and consent to local processing.',
                ),
              ),
              onChanged: (v) => setState(() => accepted = v ?? false),
            ),
            FilledButton(
              onPressed: accepted ? () => a.consent() : null,
              child: Text(a.tr('Bắt đầu', 'Continue')),
            ),
            TextButton(
              onPressed: () => a.language(!a.english),
              child: Text(a.english ? 'Tiếng Việt' : 'English'),
            ),
          ],
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int page = 0;
  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('OrthoAI'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Chip(
              label: Text(a.tr('Nghiên cứu', 'Research')),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (page) {
          0 => const Dashboard(),
          1 => const CaseHistory(),
          2 => const ReferencesScreen(),
          _ => const SettingsScreen(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (p) => setState(() => page = p),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            label: a.tr('Tổng quan', 'Home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_outlined),
            label: a.tr('Ca đã lưu', 'Cases'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            label: a.tr('Tài liệu', 'References'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            label: a.tr('Cài đặt', 'Settings'),
          ),
        ],
      ),
    );
  }
}

Future<void> enterCase(
  BuildContext context, {
  CaseRecord? record,
  String? action,
  bool fresh = false,
  int tab = 0,
}) async {
  final a = context.read<AppController>();
  final replace = record != null || fresh || a.current == null;
  if (replace && a.dirty && a.current != null) {
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          a.tr('Ca hiện tại chưa được lưu', 'Current case is unsaved'),
        ),
        content: Text(
          a.tr(
            'Tiếp tục sẽ bỏ thay đổi chưa lưu của ca hiện tại.',
            'Continuing discards unsaved changes in the current case.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(a.tr('Hủy', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(a.tr('Tiếp tục', 'Continue')),
          ),
        ],
      ),
    );
    if (discard != true || !context.mounted) return;
  }
  if (record != null) {
    try {
      if (!await a.edit(record)) return;
    } catch (_) {
      if (context.mounted) {
        showMessage(
          context,
          a.tr(
            'Không đọc được ca. Tệp đã được giữ nguyên.',
            'Cannot read this case. The file was preserved.',
          ),
        );
      }
      return;
    }
  } else if (fresh || a.current == null) {
    a.newCase();
  }
  if (context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CaseWorkspace(initialAction: action, initialTab: tab),
      ),
    );
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          a.tr(
            'Từ hình ảnh đến\nđánh giá có hệ thống.',
            'From radiograph to\nstructured assessment.',
          ),
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          a.tr(
            'Xem phim • Đo đạc • Phân loại AO/OTA 2018',
            'View • Measure • AO/OTA 2018 classification',
          ),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(20)),
          onPressed: () => enterCase(context, action: 'camera'),
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(a.tr('Chụp X-quang', 'Scan X-ray')),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(20)),
          onPressed: () => enterCase(context, action: 'import'),
          icon: const Icon(Icons.file_upload_outlined),
          label: Text(a.tr('Nhập X-quang', 'Import X-ray')),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.add),
              label: Text(a.tr('Ca mới', 'New case')),
              onPressed: () => enterCase(context, fresh: true),
            ),
            ActionChip(
              avatar: const Icon(Icons.account_tree_outlined),
              label: Text(a.tr('Phân loại AO', 'AO classification')),
              onPressed: () => enterCase(context, tab: 1),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.offline_bolt_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.tr(
                          'Cục bộ và có thể kiểm tra',
                          'Local and reviewable',
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  a.tr(
                    'Không có AI chẩn đoán. Bác sĩ xác nhận phân loại. Ba vùng: đầu dưới xương quay, đầu trên xương đùi, đầu trên xương chày.',
                    'No diagnostic AI. Clinicians confirm classifications. Three regions: distal radius, proximal femur and proximal tibia.',
                  ),
                ),
              ],
            ),
          ),
        ),
        if (a.current != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_note),
            title: Text(a.current!.id),
            subtitle: Text(
              a.dirty
                  ? a.tr('Ca đang làm • chưa lưu', 'Active case • unsaved')
                  : a.tr('Ca đang làm', 'Active case'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => enterCase(context),
          ),
        const SizedBox(height: 12),
        Text(
          a.tr('Ca gần đây', 'Recent cases'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (a.cases.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              a.tr(
                'Chưa có ca đã lưu. Bắt đầu bằng chụp hoặc nhập ảnh.',
                'No saved cases. Begin by scanning or importing an image.',
              ),
            ),
          ),
        for (final r in a.cases.take(3)) CaseTile(record: r),
      ],
    );
  }
}

class CaseTile extends StatelessWidget {
  const CaseTile({super.key, required this.record});
  final CaseRecord record;
  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(record.id),
        subtitle: Text(
          '${record.confirmedCode ?? a.tr('Chưa xác nhận', 'Unconfirmed')} • ${record.imageCount} ${a.tr('ảnh', 'images')}\n${record.updatedAt.toLocal().toString().substring(0, 16)}',
        ),
        isThreeLine: true,
        onTap: () => enterCase(context, record: record),
        trailing: IconButton(
          tooltip: a.tr('Xóa ca', 'Delete case'),
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(
                  a.tr(
                    'Xóa ca và ảnh cục bộ?',
                    'Delete this local case and images?',
                  ),
                ),
                content: Text(record.id),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: Text(a.tr('Hủy', 'Cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(a.tr('Xóa', 'Delete')),
                  ),
                ],
              ),
            );
            if (ok == true) {
              try {
                await a.delete(record.id);
              } catch (_) {
                if (context.mounted) {
                  showMessage(
                    context,
                    a.tr('Không xóa được ca.', 'Could not delete case.'),
                  );
                }
              }
            }
          },
        ),
      ),
    );
  }
}

class CaseHistory extends StatelessWidget {
  const CaseHistory({super.key});
  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          a.tr('Ca đã lưu', 'Saved cases'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        if (a.cases.isEmpty)
          Text(
            a.tr(
              'Chưa có ca đã lưu trên thiết bị này.',
              'No cases saved on this device.',
            ),
          ),
        for (final r in a.cases) CaseTile(record: r),
        if (a.repository.unreadableIds.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            a.tr(
              'Một số ca không đọc được. Các tệp vẫn được giữ nguyên; việc xóa không thể hoàn tác.',
              'Some cases could not be read. Their files were preserved; deletion cannot be undone.',
            ),
          ),
          for (final id in a.repository.unreadableIds)
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(id),
                subtitle: Text(a.tr('Không giải mã được', 'Unable to decrypt')),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: a.tr('Xóa tệp ca lỗi', 'Delete unreadable case'),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text(
                          a.tr(
                            'Xóa vĩnh viễn tệp ca này?',
                            'Permanently delete this case file?',
                          ),
                        ),
                        content: Text(id),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: Text(a.tr('Hủy', 'Cancel')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: Text(a.tr('Xóa', 'Delete')),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      try {
                        await a.delete(id);
                      } catch (_) {
                        if (context.mounted) {
                          showMessage(
                            context,
                            a.tr(
                              'Không xóa được tệp.',
                              'Could not delete the file.',
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class ReferencesScreen extends StatelessWidget {
  const ReferencesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          a.tr('Tài liệu chuyên môn', 'Clinical references'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          a.tr(
            'Liên kết nguồn chính thức. Cần mạng để mở tài liệu. Nội dung AO thuộc bản quyền của AO Foundation.',
            'Official source links. Internet is required. AO content is copyrighted by AO Foundation.',
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('AO Surgery Reference'),
            subtitle: const Text(
              'AO Foundation • surgeryreference.aofoundation.org',
            ),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => openReference(
              context,
              'https://surgeryreference.aofoundation.org/',
            ),
          ),
        ),
        for (final r in a.knowledge.regions)
          Card(
            child: ListTile(
              title: Text(a.english ? r.nameEn : r.nameVi),
              subtitle: const Text('AO/OTA 2018 • AO Surgery Reference'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => openReference(context, r.referenceUrls.first),
            ),
          ),
      ],
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppController>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          a.tr('Cài đặt & giới thiệu', 'Settings & about'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('English / Tiếng Việt'),
          value: a.english,
          onChanged: a.language,
        ),
        DropdownButtonFormField<String>(
          initialValue: a.prefs.getString('theme') ?? 'system',
          decoration: InputDecoration(
            labelText: a.tr('Giao diện', 'Appearance'),
          ),
          items: [
            DropdownMenuItem(
              value: 'system',
              child: Text(a.tr('Theo hệ thống', 'System')),
            ),
            DropdownMenuItem(
              value: 'light',
              child: Text(a.tr('Sáng', 'Light')),
            ),
            DropdownMenuItem(value: 'dark', child: Text(a.tr('Tối', 'Dark'))),
          ],
          onChanged: (v) {
            if (v != null) a.theme(v);
          },
        ),
        const SizedBox(height: 24),
        const Text('OrthoAI 0.1.0+1 • AO/OTA 2018'),
        const SizedBox(height: 12),
        Text(
          a.tr(
            'Bản nghiên cứu / giáo dục, cần bác sĩ rà soát. Chưa thẩm định chẩn đoán. Không có mô hình AI. Quy tắc hỗ trợ nhóm lớn A/B/C ở người lớn, không phân nhóm chi tiết.',
            'Research / education prototype requiring clinician review. No diagnostic validation or AI model. Adult coarse A/B/C types only; no detailed subgroups.',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          a.tr(
            'Ca được mã hóa AES-GCM; khóa trong kho an toàn của hệ điều hành. Ứng dụng không tự tải dữ liệu lên mạng. iOS có thể sao lưu tệp mã hóa theo cài đặt hệ điều hành; khóa chỉ dành cho thiết bị này. Tệp xuất tạm được dọn khi mở lại ứng dụng. Bản sao đã nhận ở ứng dụng khác nằm ngoài quyền quản lý của OrthoAI.',
            'Cases use AES-GCM with a key in OS secure storage. The app does not upload data automatically. iOS may back up encrypted files according to OS settings; keys are device-only. Temporary exports are cleared on next launch. Recipient copies are outside OrthoAI control.',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          a.tr(
            'DICOM: chỉ hỗ trợ một khung đơn sắc, little endian không nén. Chưa hỗ trợ hiệu chỉnh phối cảnh. Chất lượng ảnh chỉ được kiểm tra bằng chỉ số kỹ thuật sơ bộ.',
            'DICOM: single-frame monochrome uncompressed little endian only. Perspective correction is not supported. Image quality checks are limited technical heuristics.',
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'OrthoAI',
            applicationVersion: '0.1.0',
          ),
          icon: const Icon(Icons.info_outline),
          label: Text(a.tr('Giấy phép phần mềm', 'Software licenses')),
        ),
      ],
    );
  }
}
