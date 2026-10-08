import 'package:flutter/material.dart';
import '../core/help_content.dart';
import '../theme/shipdehop_colors.dart';
import '../widgets/contextual_help_button.dart';
import 'chat_inbox_screen.dart';
import 'orders_screen.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final TextEditingController _askController = TextEditingController();
  String _selectedCategory = 'All';
  String _activeSearchQuery = '';
  bool _hasSearched = false;
  List<HelpTopic> _searchResults = [];

  final List<String> _popularQuestions = [
    'How does ParcelPool work?',
    'Is my payment protected?',
    'What can I carry?',
    'How do I find a ride?',
    'What is the difference between Trust Score and Progress?',
  ];

  @override
  void dispose() {
    _askController.dispose();
    super.dispose();
  }

  void _runSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _activeSearchQuery = '';
        _hasSearched = false;
        _searchResults = [];
      });
      return;
    }

    final results = HelpContent.search(q);
    setState(() {
      _activeSearchQuery = q;
      _hasSearched = true;
      _searchResults = results;
    });
  }

  void _onPopularQuestionTap(String question) {
    _askController.text = question;
    _runSearch(question);
  }

  @override
  Widget build(BuildContext context) {
    final allTopics = HelpContent.allTopics;
    final categories = ['All', ...allTopics.map((t) => t.category).toSet()];

    List<HelpTopic> categoryFilteredTopics = allTopics;
    if (_selectedCategory != 'All') {
      categoryFilteredTopics = allTopics.where((t) => t.category == _selectedCategory).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Need help with something happening now?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SupportActionCard(
                      icon: Icons.receipt_long_outlined,
                      title: 'My activity',
                      subtitle: 'Open an order, ride or parcel',
                      onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const OrdersScreen())),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SupportActionCard(
                      icon: Icons.forum_outlined,
                      title: 'Messages',
                      subtitle: 'Talk to your counterparty',
                      onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const ChatInboxScreen())),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // ASK SHIPDEHOP HEADER CARD
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: Colors.indigo.shade50.withValues(alpha: 0.6),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome, color: Colors.indigo),
                          SizedBox(width: 8),
                          Text(
                            'Ask ShipdeHop',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ask anything about how ShipdeHop works.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _askController,
                        onSubmitted: _runSearch,
                        decoration: InputDecoration(
                          hintText: 'e.g. How does parcel matching work?',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_askController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _askController.clear();
                                    _runSearch('');
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.send, color: Colors.indigo),
                                onPressed: () => _runSearch(_askController.text),
                              ),
                            ],
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.indigo.shade100),
                          ),
                        ),
                      ),
                      if (_hasSearched) ...[
                        const SizedBox(height: 16),
                        if (_searchResults.isNotEmpty) ...[
                          Text(
                            'Results for "$_activeSearchQuery":',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo),
                          ),
                          const SizedBox(height: 8),
                          ..._searchResults.map(
                            (topic) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                  dense: true,
                                  title: Text(topic.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(topic.shortExplanation),
                                  trailing: const Icon(Icons.chevron_right, size: 18),
                                  onTap: () => ContextualHelpButton.showHelpModal(context, topic.id),
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.amber, size: 20),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "I don't have an answer for that yet. Try one of the topics below.",
                                    style: TextStyle(fontSize: 13, color: Colors.brown),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // POPULAR QUESTIONS
              const Text(
                'Popular questions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _popularQuestions.map((q) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: const Icon(Icons.help_outline, size: 14),
                        label: Text(q, style: const TextStyle(fontSize: 12)),
                        onPressed: () => _onPopularQuestionTap(q),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 24),

              // HOW SHIPDEHOP WORKS (6 CONSUMER ACTION CARDS)
              const Text(
                'How ShipdeHop Works',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.3,
                children: [
                  _buildHubTile(context, 'Send a parcel', 'Parcels & Luggage', Icons.local_shipping, Colors.blue, 'shipster'),
                  _buildHubTile(context, 'Carry & earn', 'Travel & Earnings', Icons.card_travel, Colors.indigo, 'hopster'),
                  _buildHubTile(context, 'Find a ride', 'CarPool Rides', Icons.directions_car, Colors.green, 'pooler'),
                  _buildHubTile(context, 'Offer seats', 'Driver Commute', Icons.airline_seat_recline_extra, Colors.teal, 'poolice'),
                  _buildHubTile(context, 'Buy-for-Me', 'Global Shopping', Icons.shopping_bag, Colors.amber.shade900, 'shopster'),
                  _buildHubTile(context, 'Buy & sell', 'Local Marketplace', Icons.storefront, Colors.purple, 'lister'),
                ],
              ),

              const SizedBox(height: 24),

              // FREQUENTLY ASKED QUESTIONS (FAQS)
              const Text(
                'Frequently Asked Questions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ExpansionTile(
                title: const Text('Is my payment protected?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Yes! Payments are held safely in protection until both parties confirm a successful handoff.',
                      style: TextStyle(fontSize: 13, color: ShipdeHopColors.textSecondary),
                    ),
                  ),
                ],
              ),
              ExpansionTile(
                title: const Text('Terminology & Glossary', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Explore our terms: Shipster (parcel sender), Hopster (carrier), Pooler (rider), Poolice (driver), Shopster (buyer).',
                      style: TextStyle(fontSize: 13, color: ShipdeHopColors.textSecondary),
                    ),
                  ),
                ],
              ),
              const ExpansionTile(
                title: Text('What items can I send or carry?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Ordinary consumer electronics, personal belongings, and standard items. Prohibited, hazardous, or illegal goods are strictly blocked.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ),
                ],
              ),
              const ExpansionTile(
                title: Text('How does ride cost-sharing work?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'CarPool operates under cost-sharing rules where drivers share fuel and toll costs with passengers without commercial profit.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // BROWSE BY CATEGORY CHIPS
              const Text(
                'Browse by Category',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: categories.map((cat) {
                    final selected = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: selected,
                        onSelected: (val) {
                          if (val) setState(() => _selectedCategory = cat);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 16),

              // TERMINOLOGY & GLOSSARY (AT BOTTOM)
              const Text(
                'Help Topics & Terminology',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: categoryFilteredTopics.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final topic = categoryFilteredTopics[index];
                  return Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      title: Row(
                        children: [
                          Text(topic.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              topic.category,
                              style: const TextStyle(fontSize: 10, color: Colors.black54),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(topic.shortExplanation, style: const TextStyle(fontSize: 12)),
                      ),
                      trailing: const Icon(Icons.info_outline, size: 18),
                      onTap: () => ContextualHelpButton.showHelpModal(context, topic.id),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHubTile(BuildContext context, String title, String subtitle, IconData icon, Color color, String topicId) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => ContextualHelpButton.showHelpModal(context, topicId),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _SupportActionCard extends StatelessWidget {
  const _SupportActionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: ShipdeHopColors.brandPrimary),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 3),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: ShipdeHopColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
