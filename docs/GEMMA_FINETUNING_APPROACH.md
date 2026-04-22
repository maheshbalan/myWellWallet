# Gemma Fine-Tuning Approach for FHIR Query Generation

## Executive Summary

This document compares **Fine-Tuning** vs **RAG/Prompt Engineering** approaches for enabling Gemma to understand FHIR database queries and generate appropriate query plans. It then provides a detailed design for fine-tuning Gemma if that approach is determined to be superior.

## Comparison: Fine-Tuning vs RAG

### Fine-Tuning Approach

**How it works:**
- Train Gemma on a dataset of (natural language query → structured query plan) pairs
- Model learns to directly map queries to JSON query plans
- Inference is fast with minimal context needed

**Advantages:**
1. **Performance**: Faster inference, no need for large context windows
2. **Consistency**: Model learns patterns directly, more consistent outputs
3. **Domain Expertise**: Model becomes specialized for FHIR queries
4. **Efficiency**: Smaller context needed at inference time
5. **Complex Patterns**: Better at handling complex, multi-part queries
6. **Offline Capability**: Once trained, works completely offline

**Disadvantages:**
1. **Training Data Required**: Need to create comprehensive training dataset
2. **Update Complexity**: Adding new LOINC codes or patterns requires retraining
3. **Computational Cost**: Training requires GPU resources
4. **Deployment Complexity**: Need to manage model versions
5. **Less Flexible**: Harder to adapt to new query types without retraining

### RAG/Prompt Engineering Approach

**How it works:**
- Provide Gemma with context (schema, examples, glossary) via prompts
- Model uses context to generate query plans
- No training required

**Advantages:**
1. **No Training**: Works immediately with good prompts
2. **Easy Updates**: Update documentation, not model
3. **Flexibility**: Easy to add new query types
4. **Transparency**: Can see exactly what context is used
5. **Iteration Speed**: Fast to test and improve

**Disadvantages:**
1. **Context Size**: Requires large context windows
2. **Inference Speed**: Slower due to processing large prompts
3. **Consistency**: May vary more between similar queries
4. **Prompt Engineering**: Requires careful prompt design
5. **Token Costs**: Higher token usage (if using API-based models)

## Recommendation: Hybrid Approach

**Best of Both Worlds:**

1. **Fine-Tune Core Task**: Train Gemma to understand the fundamental mapping:
   - Natural language → Resource type
   - Medical terms → LOINC codes
   - Query structure → Filter/sort/limit parameters

2. **RAG for Context**: Use RAG for:
   - Current LOINC code mappings (updated frequently)
   - Patient-specific context
   - Recent query examples
   - Database schema details

3. **Benefits**:
   - Fast inference (fine-tuned model)
   - Easy updates (RAG context)
   - Best accuracy (specialized model + current context)

## Fine-Tuning Design (If Chosen)

### Training Data Structure

#### Input Format (Natural Language Query)
```
"show me my cholesterol levels"
"what are my recent visits"
"show me record 8 of my test results"
"find my highest glucose reading this year"
```

#### Output Format (Structured Query Plan)
```json
{
  "resourceType": "Observation",
  "filters": {
    "codeSearch": {
      "type": "loinc",
      "codes": ["2093-3", "2085-9", "2089-1", "2571-8"],
      "display": "cholesterol"
    },
    "sort": "-effectiveDateTime"
  },
  "intent": "list_cholesterol_levels",
  "fallbackToMCP": false
}
```

### Training Dataset Categories

#### 1. Resource Type Identification (500 examples)
- Visits/Encounters
- Test Results/Diagnostic Reports
- Medications
- Observations/Lab Values
- Immunizations
- Conditions

#### 2. Medical Term to LOINC Mapping (1000 examples)
- Cholesterol variations
- Glucose variations
- Blood pressure
- Common lab tests
- Vital signs

#### 3. Complex Queries (500 examples)
- Record-specific queries ("record 8")
- Date range queries ("past 6 months")
- Comparison queries ("highest", "lowest", "above 200")
- Multi-criteria queries ("active medications from last year")

#### 4. Edge Cases (200 examples)
- Ambiguous queries
- Missing information
- Invalid queries
- Multi-resource queries

### Training Data Generation Strategy

#### Phase 1: Template-Based Generation
```python
templates = [
    ("show me my {term} levels", "Observation", "loinc", ["codes"]),
    ("what are my recent {resource}", "{resource_type}", None, None),
    ("show me record {n} of my {resource}", "{resource_type}", None, {"recordIndex": n-1}),
]

# Generate variations:
# - Synonyms (cholesterol = cholesterol levels = my cholesterol)
# - Phrasing variations (show me = what are = list)
# - Context variations (recent = latest = newest)
```

#### Phase 2: Real Query Collection
- Collect actual user queries from app usage
- Manually annotate with correct query plans
- Use for validation and fine-tuning

#### Phase 3: Synthetic Augmentation
- Use GPT-4/Claude to generate variations
- Paraphrase existing queries
- Add noise and variations

### Model Architecture

#### Base Model
- **Gemma 2B** (2 billion parameters)
- Suitable for mobile deployment
- Good balance of capability and size

#### Fine-Tuning Method
- **LoRA (Low-Rank Adaptation)**: Efficient fine-tuning
  - Reduces trainable parameters by 99%
  - Faster training, smaller model size
  - Maintains base model capabilities

#### Training Configuration
```python
training_config = {
    "method": "LoRA",
    "rank": 16,
    "alpha": 32,
    "target_modules": ["q_proj", "v_proj", "k_proj", "o_proj"],
    "learning_rate": 2e-4,
    "batch_size": 8,
    "epochs": 3,
    "warmup_steps": 100,
    "max_length": 512
}
```

### Training Pipeline

#### Step 1: Data Preparation
1. Load training examples
2. Format as instruction-following pairs
3. Tokenize with Gemma tokenizer
4. Split train/validation (80/20)

#### Step 2: Model Setup
1. Load Gemma 2B base model
2. Configure LoRA adapters
3. Freeze base model weights
4. Initialize LoRA parameters

#### Step 3: Training
1. Train on training set
2. Validate on validation set
3. Monitor loss and accuracy
4. Early stopping if overfitting

#### Step 4: Evaluation
1. Test on held-out test set
2. Measure accuracy metrics:
   - Resource type accuracy
   - LOINC code mapping accuracy
   - Filter parameter accuracy
   - Overall query plan correctness

#### Step 5: Export
1. Merge LoRA weights into base model
2. Quantize model (INT8/INT4) for mobile
3. Export to ONNX or TensorFlow Lite
4. Package for Flutter integration

### Integration with Flutter App

#### Option 1: On-Device Inference
- Deploy quantized Gemma model to mobile
- Use ONNX Runtime or TensorFlow Lite
- Fast, offline, private

#### Option 2: Server-Side Inference
- Host model on server
- App sends queries via API
- More powerful hardware, always updated

#### Option 3: Hybrid
- Simple queries: On-device
- Complex queries: Server-side
- Fallback: RAG approach

### Dataset Requirements

#### Minimum Dataset Size
- **Training**: 2,000 examples
- **Validation**: 500 examples
- **Test**: 500 examples
- **Total**: 3,000 examples

#### Quality Requirements
- Diverse query phrasings
- Cover all resource types
- Include edge cases
- Accurate annotations

### Training Data Schema

```json
{
  "query": "show me my cholesterol levels",
  "query_plan": {
    "resourceType": "Observation",
    "filters": {
      "codeSearch": {
        "type": "loinc",
        "codes": ["2093-3", "2085-9", "2089-1", "2571-8"]
      },
      "sort": "-effectiveDateTime"
    },
    "intent": "list_cholesterol_levels"
  },
  "metadata": {
    "category": "medical_term_mapping",
    "difficulty": "medium",
    "resource_type": "Observation"
  }
}
```

### Evaluation Metrics

#### Accuracy Metrics
1. **Resource Type Accuracy**: % correct resource type identification
2. **LOINC Code Accuracy**: % correct LOINC code mappings
3. **Filter Accuracy**: % correct filter parameters
4. **Overall Plan Accuracy**: % completely correct query plans

#### Performance Metrics
1. **Inference Time**: Average time to generate query plan
2. **Model Size**: Size of quantized model
3. **Memory Usage**: RAM required for inference

### Update Strategy

#### When to Retrain
1. New LOINC codes added
2. New resource types supported
3. New query patterns emerge
4. Accuracy drops below threshold

#### Incremental Training
- Fine-tune on new examples only
- Use previous model as starting point
- Faster than full retraining

## Comparison Matrix

| Aspect | Fine-Tuning | RAG | Hybrid |
|--------|------------|-----|--------|
| **Training Time** | Hours | None | Hours (one-time) |
| **Inference Speed** | Fast | Medium | Fast |
| **Update Frequency** | Retrain needed | Update docs | Update docs |
| **Accuracy** | High | Medium-High | Highest |
| **Flexibility** | Medium | High | High |
| **Deployment** | Complex | Simple | Medium |
| **Cost** | Training cost | Context cost | Both |

## Recommendation

**Start with RAG, then fine-tune if needed:**

1. **Phase 1 (Current)**: Implement RAG approach
   - Fast to implement
   - Easy to iterate
   - Good for MVP

2. **Phase 2 (If needed)**: Fine-tune Gemma
   - If RAG accuracy insufficient
   - If inference speed critical
   - If query volume high

3. **Phase 3 (Optimal)**: Hybrid approach
   - Fine-tuned model for core patterns
   - RAG for context and updates
   - Best of both worlds

## Next Steps

If fine-tuning is chosen:

1. **Create Training Dataset** (Week 1-2)
   - Generate template-based examples
   - Collect real user queries
   - Annotate with query plans

2. **Set Up Training Environment** (Week 2)
   - Set up GPU environment
   - Install training libraries
   - Configure training pipeline

3. **Train Model** (Week 3)
   - Run training experiments
   - Tune hyperparameters
   - Evaluate results

4. **Integrate with App** (Week 4)
   - Export model for mobile
   - Integrate inference engine
   - Test end-to-end

5. **Deploy and Monitor** (Week 5+)
   - Deploy to production
   - Monitor accuracy
   - Collect feedback for retraining

## Conclusion

Fine-tuning offers better performance and consistency but requires more upfront work. RAG is faster to implement and more flexible. The hybrid approach combines the best of both.

**Recommendation**: Start with RAG, then fine-tune if performance requirements demand it.

