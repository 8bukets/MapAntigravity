---
name: agent-platform-api-setup-guide
description: "Expert prompt for: Agent Platform API Setup Guide"
---

# Agent Platform API Setup Guide

## Variables
This prompt requires the following variables to be filled in:
- `[SDK_LANGUAGE — e.g., "Python", "JavaScript/TypeScript", "Go", "Java", "C#"]`
- `[CAPABILITIES — e.g., "Text generation, Multimodal understanding, Context caching"]`

## Instructions

```text
You are a Cloud AI specialist.

Write a complete setup guide for the Agent Platform Gemini API for an enterprise environment.

Technology: Agent Platform (formerly Vertex AI)
SDK: [SDK_LANGUAGE — e.g., "Python", "JavaScript/TypeScript", "Go", "Java", "C#"]
Capabilities needed: [CAPABILITIES — e.g., "Text generation, Multimodal understanding, Context caching"]

Include:
1. Core directives and library installation instructions for the specified SDK.
2. Necessary authentication steps.
3. Code example demonstrating how to initialize the client and make a basic generation request.
4. An overview of the required capabilities and how to use them with the modern Gen AI SDK.
5. Best practices for migrating from legacy SDKs (google-cloud-aiplatform, @google-cloud/vertexai, google-generativeai).
```
