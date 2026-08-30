export const PASSWORD_MIN_LENGTH = 8;
export const PASSWORD_RECOMMENDED_LENGTH = 12;

export function evaluatePassword(password) {
  const value = typeof password === 'string' ? password : '';
  const hasMinimumLength = value.length >= PASSWORD_MIN_LENGTH;
  const hasLetter = /\p{L}/u.test(value);
  const hasNumber = /\p{N}/u.test(value);

  return Object.freeze({
    hasMinimumLength,
    hasLetter,
    hasNumber,
    isValid: hasMinimumLength && hasLetter && hasNumber,
    isRecommendedLength: value.length >= PASSWORD_RECOMMENDED_LENGTH,
  });
}

export function assertPasswordPolicy(password) {
  const result = evaluatePassword(password);
  if (!result.hasMinimumLength) {
    throw new Error(`Use at least ${PASSWORD_MIN_LENGTH} characters for the password.`);
  }
  if (!result.hasLetter || !result.hasNumber) {
    throw new Error('Include at least one letter and one number in the password.');
  }
  return result;
}

export const PASSWORD_POLICY_MESSAGE = 'Use at least 8 characters with a letter and a number. 12 or more is recommended.';
