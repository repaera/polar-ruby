# frozen_string_literal: true

class CreditCostCalculator
  include ActiveModel::Model

  # Define base costs for different operations
  OPERATION_COSTS = {
    'basic_api_call' => 1,
    'advanced_api_call' => 5,
    'image_processing' => 10,
    'video_processing' => 50,
    'large_file_processing' => 50,
    'data_export' => 25,
    'premium_feature_access' => 100,
    'bulk_operation' => 200,
    'ai_analysis' => 15,
    'text_processing' => 2,
    'data_transformation' => 8
  }.freeze

  # Define size-based multipliers
  SIZE_MULTIPLIERS = {
    'small' => 1.0,    # < 1MB
    'medium' => 2.0,   # 1-10MB
    'large' => 5.0,    # 10-100MB
    'xlarge' => 10.0   # > 100MB
  }.freeze

  # Define complexity multipliers
  COMPLEXITY_MULTIPLIERS = {
    'simple' => 1.0,
    'standard' => 1.5,
    'complex' => 2.5,
    'advanced' => 4.0
  }.freeze

  def self.cost_for_operation(operation_type)
    OPERATION_COSTS[operation_type.to_s] || 1
  end

  def self.calculate_cost(operation_type, parameters = {})
    new(operation_type, parameters).calculate
  end

  def initialize(operation_type, parameters = {})
    @operation_type = operation_type.to_s
    @parameters = parameters.with_indifferent_access
  end

  def calculate
    base_cost = OPERATION_COSTS[@operation_type] || 1
    
    # Apply multipliers based on parameters
    multiplier = 1.0
    multiplier *= size_multiplier
    multiplier *= complexity_multiplier
    multiplier *= quantity_multiplier
    multiplier *= priority_multiplier
    
    # Apply minimum cost rules
    final_cost = [base_cost * multiplier, minimum_cost].max
    
    # Round up to nearest 0.1 credits
    (final_cost * 10).ceil / 10.0
  end

  def cost_breakdown
    base_cost = OPERATION_COSTS[@operation_type] || 1
    
    {
      operation_type: @operation_type,
      base_cost: base_cost,
      size_multiplier: size_multiplier,
      complexity_multiplier: complexity_multiplier,
      quantity_multiplier: quantity_multiplier,
      priority_multiplier: priority_multiplier,
      total_multiplier: size_multiplier * complexity_multiplier * quantity_multiplier * priority_multiplier,
      final_cost: calculate,
      parameters_used: relevant_parameters
    }
  end

  private

  def size_multiplier
    return 1.0 unless @parameters[:file_size] || @parameters[:data_size]
    
    size_bytes = (@parameters[:file_size] || @parameters[:data_size]).to_i
    
    case size_bytes
    when 0..1.megabyte
      SIZE_MULTIPLIERS['small']
    when 1.megabyte..10.megabytes
      SIZE_MULTIPLIERS['medium']
    when 10.megabytes..100.megabytes
      SIZE_MULTIPLIERS['large']
    else
      SIZE_MULTIPLIERS['xlarge']
    end
  end

  def complexity_multiplier
    complexity = @parameters[:complexity]&.to_s&.downcase
    return 1.0 unless complexity
    
    COMPLEXITY_MULTIPLIERS[complexity] || 1.0
  end

  def quantity_multiplier
    quantity = @parameters[:quantity]&.to_i || 1
    
    # Bulk processing gets slight volume discount after 10 items
    case quantity
    when 1..10
      quantity
    when 11..100
      quantity * 0.9  # 10% discount
    when 101..1000
      quantity * 0.8  # 20% discount
    else
      quantity * 0.7  # 30% discount
    end
  end

  def priority_multiplier
    priority = @parameters[:priority]&.to_s&.downcase
    
    case priority
    when 'low'
      0.8  # 20% discount for low priority
    when 'standard', 'normal', nil
      1.0
    when 'high'
      1.5  # 50% premium for high priority
    when 'urgent', 'immediate'
      2.0  # 100% premium for urgent
    else
      1.0
    end
  end

  def minimum_cost
    # Some operations have minimum costs regardless of parameters
    case @operation_type
    when 'premium_feature_access'
      100  # Always costs at least 100 credits
    when 'bulk_operation'
      50   # Minimum 50 credits for any bulk operation
    when 'ai_analysis'
      5    # Minimum 5 credits for AI analysis
    else
      0.1  # General minimum of 0.1 credits
    end
  end

  def relevant_parameters
    used_params = {}
    
    used_params[:file_size] = @parameters[:file_size] if @parameters[:file_size]
    used_params[:data_size] = @parameters[:data_size] if @parameters[:data_size]
    used_params[:complexity] = @parameters[:complexity] if @parameters[:complexity]
    used_params[:quantity] = @parameters[:quantity] if @parameters[:quantity]
    used_params[:priority] = @parameters[:priority] if @parameters[:priority]
    
    used_params
  end

  # Helper methods for common operation cost estimates
  def self.estimate_api_call_cost(complexity: 'standard', priority: 'normal')
    operation_type = complexity == 'simple' ? 'basic_api_call' : 'advanced_api_call'
    calculate_cost(operation_type, { complexity: complexity, priority: priority })
  end

  def self.estimate_file_processing_cost(file_size:, processing_type: 'standard')
    operation_type = case processing_type.to_s
                    when 'image'
                      'image_processing'
                    when 'video'
                      'video_processing'
                    else
                      'large_file_processing'
                    end
    
    calculate_cost(operation_type, { file_size: file_size })
  end

  def self.estimate_bulk_operation_cost(quantity:, operation_type: 'bulk_operation')
    calculate_cost(operation_type, { quantity: quantity })
  end

  def self.estimate_ai_analysis_cost(data_size:, complexity: 'standard')
    calculate_cost('ai_analysis', { 
      data_size: data_size, 
      complexity: complexity 
    })
  end

  # Volume discount calculator
  def self.calculate_volume_discount(total_credits_monthly)
    case total_credits_monthly
    when 0..1000
      0 # No discount
    when 1001..5000
      5 # 5% discount
    when 5001..15000
      10 # 10% discount
    when 15001..50000
      15 # 15% discount
    else
      20 # 20% discount for enterprise usage
    end
  end
end