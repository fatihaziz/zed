use crate::{db::UserId, Config};
use anyhow::{anyhow, Result};
use chrono::Utc;
use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use thiserror::Error;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LlmTokenClaims {
    pub iat: u64,
    pub exp: u64,
    pub jti: String,
    pub user_id: u64,
    pub is_staff: bool,
    pub plan: rpc::proto::Plan,
}

const LLM_TOKEN_LIFETIME: Duration = Duration::from_secs(60 * 60);

impl LlmTokenClaims {
    pub fn create(
        user_id: UserId,
        is_staff: bool,
        plan: rpc::proto::Plan,
        config: &Config,
    ) -> Result<String> {
        let secret = config
            .llm_api_secret
            .as_ref()
            .ok_or_else(|| anyhow!("no LLM API secret"))?;

        let now = Utc::now();
        let claims = Self {
            iat: now.timestamp() as u64,
            exp: (now + LLM_TOKEN_LIFETIME).timestamp() as u64,
            jti: uuid::Uuid::new_v4().to_string(),
            user_id: user_id.to_proto(),
            is_staff,
            plan,
        };

        Ok(jsonwebtoken::encode(
            &Header::default(),
            &claims,
            &EncodingKey::from_secret(secret.as_ref()),
        )?)
    }

    pub fn validate(token: &str, config: &Config) -> Result<LlmTokenClaims, ValidateLlmTokenError> {
        let secret = config
            .llm_api_secret
            .as_ref()
            .ok_or_else(|| anyhow!("no LLM API secret"))?;

        match jsonwebtoken::decode::<Self>(
            token,
            &DecodingKey::from_secret(secret.as_ref()),
            &Validation::default(),
        ) {
            Ok(token) => Ok(token.claims),
            Err(e) => {
                if e.kind() == &jsonwebtoken::errors::ErrorKind::ExpiredSignature {
                    Err(ValidateLlmTokenError::Expired)
                } else {
                    Err(ValidateLlmTokenError::JwtError(e))
                }
            }
        }
    }
}

#[derive(Error, Debug)]
pub enum ValidateLlmTokenError {
    #[error("access token is expired")]
    Expired,
    #[error("access token validation error: {0}")]
    JwtError(#[from] jsonwebtoken::errors::Error),
    #[error("{0}")]
    Other(#[from] anyhow::Error),
}
