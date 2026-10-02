import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final TextEditingController _geminiKeyController = TextEditingController();
  final FocusNode _geminiKeyFocusNode = FocusNode();
  late TextEditingController _backendUrlController;
  late FocusNode _backendUrlFocusNode;


  @override
  void initState() {
    super.initState();
    _backendUrlFocusNode = FocusNode();
    _backendUrlFocusNode.addListener(() {
      setState(() {});
    });
    _geminiKeyFocusNode.addListener(() {
      setState(() {});
    });
    final provider = Provider.of<ChatProvider>(context, listen: false);
    _backendUrlController = TextEditingController(text: provider.backendUrl);
  
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    _backendUrlFocusNode.dispose();
    _geminiKeyController.dispose();
    _geminiKeyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context);
    final theme = Theme.of(context);

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: theme.dividerColor.withOpacity(0.1))),
      ),
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.blue[700]!, Colors.indigo[800]!],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'DeskMate',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                'Open Source AI',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildStatusCard(provider, theme),
                    const SizedBox(height: 16),
                    _buildModeSelector(provider, theme),
                    if (provider.mode == AgentMode.personal) ...[
                      const SizedBox(height: 16),
                      _buildPersonalHealthCard(provider, theme),
                    ],
                    const SizedBox(height: 24),
                    Text('CONFIGURATION', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.5, color: Colors.black87)),
                    const SizedBox(height: 16),
                    _buildGeminiInput(provider, theme),
                    const SizedBox(height: 16),
                    _buildBackendUrlInput(provider, theme),
                    const SizedBox(height: 12),

                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelector(ChatProvider provider, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => provider.switchMode(AgentMode.deskMate),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: provider.mode == AgentMode.deskMate ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: provider.mode == AgentMode.deskMate
                      ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open_rounded,
                        size: 16,
                        color: provider.mode == AgentMode.deskMate ? theme.colorScheme.primary : Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'File Explorer',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: provider.mode == AgentMode.deskMate ? Colors.black : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => provider.switchMode(AgentMode.personal),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: provider.mode == AgentMode.personal ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: provider.mode == AgentMode.personal
                      ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_rounded,
                        size: 16,
                        color: provider.mode == AgentMode.personal ? theme.colorScheme.primary : Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Personal Agent',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: provider.mode == AgentMode.personal ? Colors.black : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalHealthCard(ChatProvider provider, ThemeData theme) {
    final health = provider.personalAgentHealth;
    final checks = health['checks'] as Map<String, dynamic>? ?? {};
    final status = health['status'] as String? ?? 'loading';

    if (status == 'loading') {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (status == 'offline') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red[100]!),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Personal Agent server unreachable.',
                style: TextStyle(fontSize: 11, color: Colors.red[900], fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    final hasCredsFile = checks['google_credentials_file'] ?? false;
    final hasGmailToken = checks['gmail_token'] ?? false;
    final hasCalToken = checks['calendar_token'] ?? false;
    final hasDriveToken = checks['drive_token'] ?? false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PERSONAL SERVICES HEALTH',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1),
          ),
          const SizedBox(height: 10),
          _buildHealthRow('Credentials JSON', hasCredsFile),
          const SizedBox(height: 6),
          _buildHealthRow('Gmail Access', hasGmailToken),
          const SizedBox(height: 6),
          _buildHealthRow('Calendar Access', hasCalToken),
          const SizedBox(height: 6),
          _buildHealthRow('Drive Access', hasDriveToken),
        ],
      ),
    );
  }

  Widget _buildHealthRow(String label, bool isOk) {
    return Row(
      children: [
        Icon(
          isOk ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 14,
          color: isOk ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isOk ? Colors.black87 : Colors.grey[600],
              fontWeight: isOk ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildStatusCard(ChatProvider provider, ThemeData theme) {
    final isOnline = provider.isBackendOnline;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOnline ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                isOnline ? 'Backend Online' : 'Backend Offline',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.history_edu_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  provider.conversationId.isEmpty 
                      ? 'No active session' 
                      : 'Session: ${provider.conversationId.substring(0, 8)}...',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                provider.isUsingGemini ? Icons.auto_awesome : Icons.memory,
                size: 16,
                color: provider.isUsingGemini 
                    ? Colors.deepPurple 
                    : (provider.isLocalLlmOnline ? Colors.green : Colors.red),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  provider.isUsingGemini 
                      ? 'Gemini (Flash) Active' 
                      : (provider.isLocalLlmOnline ? 'Local LLM Active' : 'Local LLM Offline'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: provider.isUsingGemini 
                        ? Colors.deepPurple 
                        : (provider.isLocalLlmOnline ? Colors.green : Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

   Widget _buildGeminiInput(ChatProvider provider, ThemeData theme) {
     return ConstrainedBox(
       constraints: const BoxConstraints(maxWidth: 400),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Text('Gemini API Key', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
           const SizedBox(height: 8),
           TextField(
             controller: _geminiKeyController,
             obscureText: !_geminiKeyFocusNode.hasFocus,
             focusNode: _geminiKeyFocusNode,
             decoration: InputDecoration(
               prefixIcon: const Icon(Icons.vpn_key_outlined, size: 18),
               hintText: 'Enter Gemini API Key',
               border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black)),
               enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black)),
               focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black, width: 2)),
             ),
           ),
           const SizedBox(height: 8),
           SizedBox(
             width: double.infinity,
             child: ElevatedButton.icon(
               onPressed: () {
                 provider.setGeminiApiKey(_geminiKeyController.text);
                 // clear field after setting
                 _geminiKeyController.clear();
                 // dismiss keyboard
                 FocusScope.of(context).unfocus();
               },
               icon: const Icon(Icons.vpn_key),
               label: const Text('Load Gemini API'),
             ),
           ),
         ],
       ),
     );
   }

   Widget _buildBackendUrlInput(ChatProvider provider, ThemeData theme) {
     return ConstrainedBox(
       constraints: const BoxConstraints(maxWidth: 400),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Text('Backend URL', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
           const SizedBox(height: 8),
           TextField(
             controller: _backendUrlController,
             focusNode: _backendUrlFocusNode,
             decoration: InputDecoration(
               prefixIcon: const Icon(Icons.link, size: 18),
               hintText: 'Enter Backend URL',
               border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black)),
               enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black)),
               focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black, width: 2)),
             ),
             onSubmitted: (value) {
               provider.setBackendUrl(value);
             },
           ),
           const SizedBox(height: 8),
           SizedBox(
             width: double.infinity,
             child: ElevatedButton.icon(
               onPressed: () {
                 provider.setBackendUrl(_backendUrlController.text);
                 FocusScope.of(context).unfocus();
               },
               icon: const Icon(Icons.save),
               label: const Text('Save URL'),
             ),
           ),
         ],
       ),
     );
   }



  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required FocusNode focusNode,
    bool obscure = false,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure && !focusNode.hasFocus,
          focusNode: focusNode,
          onChanged: onChanged,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18),
            hintText: 'Enter $label',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black, width: 2)),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Column(
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('v1.0.0', style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54)),
            const SizedBox(width: 8),
            const Icon(Icons.circle, size: 4, color: Colors.black54),
            const SizedBox(width: 8),
            const Text('Production Ready', style: TextStyle(fontSize: 10, color: Colors.black87)),
          ],
        ),
      ],
    );
  }
}
