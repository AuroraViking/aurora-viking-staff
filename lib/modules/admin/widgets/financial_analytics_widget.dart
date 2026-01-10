// Financial Analytics Widget for Admin Reports
// Location: lib/modules/admin/widgets/financial_analytics_widget.dart

import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';

/// Financial constants for Aurora Viking operations
/// Revenue: 12,500 ISK per seat (after costs/taxes)
/// Guide: 75,000 ISK per guide going out
/// Fuel + Road Tax: 10,000 ISK per tour
/// Overhead: 2,500,000 ISK monthly
class FinancialConstants {
  static const double revenuePerSeat = 12500;
  static const double guidePaymentPerGuide = 75000;
  static const double fuelAndRoadTaxPerTour = 10000;
  static const double monthlyOverhead = 2500000;
}

class FinancialAnalyticsWidget extends StatelessWidget {
  final int totalPassengers;
  final int totalTours; // Number of tour nights
  final int totalGuidesWorked; // Total guide shifts across all tours

  const FinancialAnalyticsWidget({
    super.key,
    required this.totalPassengers,
    required this.totalTours,
    required this.totalGuidesWorked,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate financials based on ACTUAL data
    final revenue = totalPassengers * FinancialConstants.revenuePerSeat;
    final guideCosts = totalGuidesWorked * FinancialConstants.guidePaymentPerGuide;
    final fuelCosts = totalTours * FinancialConstants.fuelAndRoadTaxPerTour;
    final totalVariableCosts = guideCosts + fuelCosts;
    final grossMargin = revenue - totalVariableCosts;
    final netMargin = grossMargin - FinancialConstants.monthlyOverhead;
    
    // Per-tour averages
    final avgPassengersPerTour = totalTours > 0 ? totalPassengers / totalTours : 0.0;
    final avgGuidesPerTour = totalTours > 0 ? totalGuidesWorked / totalTours : 0.0;
    final avgRevenuePerTour = totalTours > 0 ? revenue / totalTours : 0.0;
    final avgCostPerTour = totalTours > 0 ? totalVariableCosts / totalTours : 0.0;
    final avgMarginPerTour = avgRevenuePerTour - avgCostPerTour;
    
    // Break-even (based on average guides per tour)
    final breakEvenCostPerTour = (avgGuidesPerTour * FinancialConstants.guidePaymentPerGuide) + 
                                  FinancialConstants.fuelAndRoadTaxPerTour;
    final breakEvenPassengers = FinancialConstants.revenuePerSeat > 0 
        ? breakEvenCostPerTour / FinancialConstants.revenuePerSeat 
        : 0.0;
    final isAboveBreakEven = avgPassengersPerTour >= breakEvenPassengers;
    
    // Tours needed to cover overhead
    final toursNeededForOverhead = avgMarginPerTour > 0 
        ? (FinancialConstants.monthlyOverhead / avgMarginPerTour).ceil()
        : 0;
    
    final isProfitable = netMargin > 0;
    final profitabilityColor = isProfitable ? Colors.green : Colors.red;

    if (totalTours == 0 && totalPassengers == 0 && totalGuidesWorked == 0) {
      return _buildNoDataWidget(context);
    }

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
        
        // THE BIG NUMBER
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
                'Net margin after ${_formatCurrency(FinancialConstants.monthlyOverhead)} overhead',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Revenue vs Costs
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
              'Guides + Fuel/Road',
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
              'Before overhead',
              grossMargin >= 0 ? Colors.blue : Colors.red,
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildFinanceCard(
              '🏢 Overhead',
              _formatCurrency(FinancialConstants.monthlyOverhead),
              'Fixed monthly',
              Colors.purple,
            )),
          ],
        ),
        
        const SizedBox(height: 24),
        
        // VARIABLE COST BREAKDOWN
        Text(
          '📊 Variable Cost Breakdown',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              _buildCostBreakdownRow(
                '👤 Guide Payments',
                '$totalGuidesWorked guides × ${_formatCurrency(FinancialConstants.guidePaymentPerGuide)}',
                guideCosts,
                totalVariableCosts,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildCostBreakdownRow(
                '⛽ Fuel & Road Tax',
                '$totalTours tours × ${_formatCurrency(FinancialConstants.fuelAndRoadTaxPerTour)}',
                fuelCosts,
                totalVariableCosts,
                Colors.amber.shade700,
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // PER-TOUR AVERAGES
        Text(
          '🚌 Per-Tour Averages',
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
                'Avg guides/tour',
                avgGuidesPerTour.toStringAsFixed(1),
                '${_formatCurrency(avgGuidesPerTour * FinancialConstants.guidePaymentPerGuide)} cost',
                Colors.blue,
              ),
              const Divider(),
              _buildAnalysisRow(
                'Break-even point',
                '${breakEvenPassengers.toStringAsFixed(1)} pax',
                'At ${avgGuidesPerTour.toStringAsFixed(1)} guides avg',
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
        
        // OVERHEAD PROGRESS
        Text(
          '🎯 Monthly Target Progress',
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
        
        // QUICK REFERENCE
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '📋 Quick Reference',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildQuickStat('Revenue/Pax', _formatCurrency(FinancialConstants.revenuePerSeat)),
                  _buildQuickStat('Guide Pay', _formatCurrency(FinancialConstants.guidePaymentPerGuide)),
                  _buildQuickStat('Fuel/Tour', _formatCurrency(FinancialConstants.fuelAndRoadTaxPerTour)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoDataWidget(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Icon(Icons.analytics_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'No tour data available for this period',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Financial analytics will appear once tour reports are generated',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
          Text(title, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildCostBreakdownRow(String label, String detail, double amount, double total, Color color) {
    final percentage = total > 0 ? (amount / total * 100) : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(_formatCurrency(amount), style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total > 0 ? amount / total : 0,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('${percentage.toStringAsFixed(0)}%', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 2),
        Text(detail, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _buildAnalysisRow(String label, String value, String note, Color noteColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: noteColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(note, style: TextStyle(fontSize: 11, color: noteColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetProgress(String label, double current, double target, Color color) {
    final progress = target > 0 ? (current / target).clamp(0.0, 1.5) : 0.0;
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
              style: TextStyle(fontWeight: FontWeight.bold, color: isComplete ? Colors.green : color),
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
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  String _formatCurrency(double amount) {
    final isNegative = amount < 0;
    final absAmount = amount.abs();
    
    if (absAmount >= 1000000) {
      return '${isNegative ? '-' : ''}${(absAmount / 1000000).toStringAsFixed(2)}M ISK';
    } else if (absAmount >= 1000) {
      return '${isNegative ? '-' : ''}${(absAmount / 1000).toStringAsFixed(0)}K ISK';
    }
    return '${isNegative ? '-' : ''}${absAmount.toStringAsFixed(0)} ISK';
  }
}
