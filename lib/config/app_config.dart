/// App configuration for API keys and authentication.
/// 
/// Note: In production, these should be loaded from environment variables
/// or a secure configuration management system.
class AppConfig {
  // Google Gemini API (Moved to AWS Lambda)
  static const String geminiApiKey = ''; 
  
  // AWS Cognito Configuration (muscle_mirror dedicated pool)
  static const String awsRegion = 'ap-northeast-1';
  static const String userPoolId = 'ap-northeast-1_V0dqqG0Ib';
  
  // Cognito App Client ID
  static const String userPoolClientId = '4ojrrp2e20ssg0mk6s3a1542jc';
  
  // API Gateway endpoints
  static const String apiBaseUrl = 'https://j0yc8bklol.execute-api.ap-northeast-1.amazonaws.com/dev';

  // Cognito Domain
  static const String cognitoDomain = 'muscle-mirror-dev.auth.ap-northeast-1.amazoncognito.com';

  // Social Login Configuration
  static const String googleClientId = '8193700917-4j46cso19nr4b8orvme1it4i41n0becf.apps.googleusercontent.com';
  static const String lineChannelId = '2009046600';

  // Legal URLs
  static const String termsOfServiceUrl = 'https://nishimotoworks2025.github.io/privacy-policy-musclemirror/about.html';
  static const String privacyPolicyUrl = 'https://nishimotoworks2025.github.io/privacy-policy-musclemirror/index.html';
  static const String contactUrl = 'https://nishimotoworks2025.github.io/privacy-policy-musclemirror/contact.html';
  static const String accountDeletionUrl = 'https://nishimotoworks2025.github.io/privacy-policy-musclemirror/deletion.html';
}
