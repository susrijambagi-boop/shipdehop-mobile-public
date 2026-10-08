import { config } from '../../config.js';
import { defaultAadhaarSessionStore } from './sessionStore.js';
import { AadhaarSessionStore, AadhaarVerificationProvider } from './types.js';
import { UidaiPreprodProvider } from './uidaiPreprodProvider.js';
import { UidaiProductionProvider } from './uidaiProductionProvider.js';

export function getAadhaarProvider(sessionStore: AadhaarSessionStore = defaultAadhaarSessionStore): AadhaarVerificationProvider {
  // Hard safety guard: UIDAI_PREPROD is TEST/PREPRODUCTION ONLY and can NEVER be called in production
  if (config.NODE_ENV === 'production' && config.AADHAAR_PROVIDER === 'UIDAI_PREPROD') {
    throw new Error('UIDAI_PREPROD_FORBIDDEN_IN_PRODUCTION: UIDAI Pre-Production provider cannot be activated or called in production environment.');
  }

  switch (config.AADHAAR_PROVIDER) {
    case 'UIDAI_PREPROD':
      return new UidaiPreprodProvider(sessionStore);
    case 'UIDAI_PRODUCTION':
      return new UidaiProductionProvider(sessionStore);
    default:
      if (config.NODE_ENV === 'production') {
        return new UidaiProductionProvider(sessionStore);
      }
      return new UidaiPreprodProvider(sessionStore);
  }
}
