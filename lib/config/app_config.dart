class AppConfig {
  /// The URL for the MedGemma 4B IT GGUF model file.
  /// Using unsloth's Q4_K_M quantization which is ~2.5GB.
  static const String gemmaModelUrl = 'https://huggingface.co/unsloth/medgemma-4b-it-GGUF/resolve/main/medgemma-4b-it-Q4_K_M.gguf';

  /// The filename to save the model as locally.
  static const String gemmaModelFileName = 'medgemma-4b-it-Q4_K_M.gguf';

  /// FHIR MCP Server configuration
  static const String mcpBaseUrl = 'https://mcp-fhir-server.com';
  static const String mcpApiKey = '9mgmf20y4hRDq6-VuvHM8E5PRUQJDLVHI0gB_pFMiTY';
}
