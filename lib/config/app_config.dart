class AppConfig {
  /// The URL for the Gemma 2 2B IT GGUF model file.
  /// Using MaziyarPanahi's Q2_K quantization which is ~1.2GB.
  static const String gemmaModelUrl = 'https://huggingface.co/MaziyarPanahi/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it.Q2_K.gguf';

  /// The filename to save the model as locally.
  static const String gemmaModelFileName = 'gemma-2-2b-it.Q2_K.gguf';

  /// FHIR MCP Server configuration
  static const String mcpBaseUrl = 'https://mcp-fhir-server.com';
  static const String mcpApiKey = '9mgmf20y4hRDq6-VuvHM8E5PRUQJDLVHI0gB_pFMiTY';
}
