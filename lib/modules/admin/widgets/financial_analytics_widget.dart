// Financial Analytics Widget for Admin Reports
// Add this to lib/modules/admin/widgets/financial_analytics_widget.dart

import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';

/// Financial constants for Aurora Viking operations
class FinancialConstants {
  static const double revenuePerSeat = 12500; // ISK after costs and taxes
  static const double guidePaymentPerTour = 75000; // ISK
  static const double fuelAndRoadTaxPerTour = 7500; // ISK
  static const double monthlyOverhead = 2500000; // ISK
  
  static double get variableCostPerTour => guidePaymentPerTour + fuelAndRoadTaxPerTour; // 82,500 ISK
  static double get breakEvenPassengersPerTour => variableCostPerTour / revenuePerSeat; // ~6.6
}

class FinancialAnalyticsWidget extends StatelessWidget {
  final int totalPassengers;
  final int totalTours;
  final int? totalGuides; // Optional - for guide utilization stats

  const FinancialAnalyticsWidget({
    super.key,
    required this.totalPassengers,
    required this.totalTours,
    this.totalGuides,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate financials
    final revenue = totalPassengers * FinancialConstants.revenuePerSeat;
    final guideCosts = totalTours * FinancialConstants.guidePaymentPerTour;
    final fuelCosts = totalTours * FinancialConstants.fuelAndRoadTaxPerTour;
    final totalVariableCosts = totalTours * FinancialConstants.variableCostPerTour;
    final grossMargin = revenue - totalVariableCosts;
    final netMargin = grossMargin - FinancialConstants.monthlyOverhead;
    
    // Per-tour averages
    final avgPassengersPerTour = totalTours > 0 ? totalPassengers / totalTours : 0.0;
    final avgRevenuePerTour = totalTours > 0 ? revenue / totalTours : 0.0;
    final avgMarginPerTour = avgRevenuePerTour - FinancialConstants.variableCostPerTour;
    
    // Break-even analysis
    final breakEvenPassengers = FinancialConstants.breakEvenPassengersPerTour;
    final isAboveBreakEven = avgPassengersPerTour >= breakEvenPassengers;
    
    // Tours needed to cover overhead
    final toursNeededForOverhead = avgMarginPerTour > 0 
        ? (FinancialConstants.monthlyOverhead / avgMarginPerTour).ceil()
        : 0;
    
    // Profitability status
    final isProfitable = netMargin > 0;
    final profitabilityColor = isProfitable ? Colors.green : Colors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '💰 Financial Analytics',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 16),
        
        // Revenue & Costs Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isProfitable 
                  ? [Colors.green.shade50, Colors.green.shade100]
                  : [Colors.red.shade50, Colors.red.shade100],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: profitabilityColor.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isProfitable ? '🎉 PROFITABLE' : '⚠️ LOSS',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: profitabilityColor,
                    ),
                  ),
                  Text(
                    _formatCurrency(netMargin),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: profitabilityColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Net margin after overhead',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Financial breakdown cards
        Row(
          children: [
            Expanded(child: _buildFinanceCard(
              '📈 Revenue',
              _formatCurrency(revenue),
              '$totalPassengers pax × ${_formatCurrency(FinancialConstants.revenuePerSeat)}',
              Colors.green,
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildFinanceCard(
              '📉 Variable Costs',
              _formatCurrency(totalVariableCosts),
              '$totalTours tours × ${_formatCurrency(FinancialConstants.variableCostPerTour)}',
              Colors.orange,
            )),
          ],
        ),
        
        const SizedBox(height: 12),
        
        Row(
          children: [
            Expanded(child: _buildFinanceCard(
              '💼 Gross Margin',
              _formatCurrency(grossMargin),
              'Revenue - Variable Costs',
              grossMargin >= 0 ? Colors.blue : Colors.red,
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildFinanceCard(
              '🏢 Overhead',
              _formatCurrency(FinancialConstants.monthlyOverhead),
              'Fixed monthly cost',
              Colors.purple,
            )),
          ],
        ),
        
        const SizedBox(height: 24),
        
        // Cost Breakdown
        Text(
          '📊 Variable Costs Breakdown',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              _buildCostRow('👤 Guide payments', guideCosts, totalVariableCosts, totalTours),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _buildCostRow('⛽ Fuel & road tax', fuelCosts, totalVariableCosts, totalTours),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Variable Costs',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  Text(
                    _formatCurrency(totalVariableCosts),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: totalVariableCosts > 0 ? Colors.orange.shade700 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              if (totalTours > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Based on $totalTours tour${totalTours > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  'Per tour: ${_formatCurrency(FinancialConstants.variableCostPerTour)} (${_formatCurrency(FinancialConstants.guidePaymentPerTour)} guide + ${_formatCurrency(FinancialConstants.fuelAndRoadTaxPerTour)} fuel)',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Per-Tour Analysis
        Text(
          '🚌 Per-Tour Analysis',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _buildAnalysisRow(
                'Avg passengers/tour',
                avgPassengersPerTour.toStringAsFixed(1),
                isAboveBreakEven ? '✅ Above break-even' : '⚠️ Below break-even',
                isAboveBreakEven ? Colors.green : Colors.red,
              ),
              const Divider(),
              _buildAnalysisRow(
                'Break-even point',
                '${breakEvenPassengers.toStringAsFixed(1)} pax',
                'Min passengers needed',
                Colors.grey,
              ),
              const Divider(),
              _buildAnalysisRow(
                'Avg margin/tour',
                _formatCurrency(avgMarginPerTour),
                avgMarginPerTour > 0 ? 'Contribution margin' : 'Loss per tour',
                avgMarginPerTour > 0 ? Colors.green : Colors.red,
              ),
              if (avgMarginPerTour > 0) ...[
                const Divider(),
                _buildAnalysisRow(
                  'Tours to cover overhead',
                  '$toursNeededForOverhead tours',
                  totalTours >= toursNeededForOverhead 
                      ? '✅ Target reached!'
                      : '${toursNeededForOverhead - totalTours} more needed',
                  totalTours >= toursNeededForOverhead ? Colors.green : Colors.orange,
                ),
              ],
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Profitability Targets
        Text(
          '🎯 Monthly Targets',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        _buildTargetProgress(
          'Overhead Coverage',
          grossMargin,
          FinancialConstants.monthlyOverhead,
          Colors.purple,
        ),
        
        const SizedBox(height: 16),
        
        // Quick Stats
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildQuickStat('Revenue/Pax', _formatCurrency(FinancialConstants.revenuePerSeat)),
              _buildQuickStat('Cost/Tour', _formatCurrency(FinancialConstants.variableCostPerTour)),
              _buildQuickStat('Break-even', '${breakEvenPassengers.ceil()} pax'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFinanceCard(String title, String value, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostRow(String label, double amount, double total, int totalTours) {
    final percentage = total > 0 ? (amount / total * 100) : 0;
    final perTourAmount = totalTours > 0 ? amount / totalTours : (label.contains('Guide') ? 75000.0 : 7500.0);
    
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              if (totalTours > 0)
                Text(
                  '${_formatCurrency(perTourAmount)} × $totalTours tour${totalTours > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: LinearProgressIndicator(
            value: total > 0 ? amount / total : 0,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: Text(
            _formatCurrency(amount),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            total > 0 ? '${percentage.toStringAsFixed(0)}%' : '-',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisRow(String label, String value, String note, Color noteColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: noteColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              note,
              style: TextStyle(fontSize: 11, color: noteColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetProgress(String label, double current, double target, Color color) {
    final progress = (current / target).clamp(0.0, 1.5);
    final percentage = (progress * 100).toStringAsFixed(0);
    final isComplete = current >= target;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(
              isComplete ? '✅ $percentage%' : '$percentage%',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isComplete ? Colors.green : color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(isComplete ? Colors.green : color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatCurrency(current)} / ${_formatCurrency(target)}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildQuickStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  String _formatCurrency(double amount) {
    final isNegative = amount < 0;
    final absAmount = amount.abs();
    
    if (absAmount >= 1000000) {
      return '${isNegative ? '-' : ''}${(absAmount / 1000000).toStringAsFixed(1)}M ISK';
    } else if (absAmount >= 1000) {
      return '${isNegative ? '-' : ''}${(absAmount / 1000).toStringAsFixed(0)}K ISK';
    }
    return '${isNegative ? '-' : ''}${absAmount.toStringAsFixed(0)} ISK';
  }
}

