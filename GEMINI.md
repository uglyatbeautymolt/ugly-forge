# Gemini CLI Project Instructions

Always read and adhere to the context and rules defined in:
- [FORGE-CONTEXT.md](./FORGE-CONTEXT.md)

## Core Procedures
- **Authentication:** If git push fails in `ugly-forge`, extract the `GITHUB_TOKEN` from the `ugly-stack` remote URL and update the origin URL in `ugly-forge`:
  ```bash
  TOKEN=$(cd ../ugly-stack && git remote -v | head -n 1 | awk '{print $2}' | cut -d'/' -f3 | cut -d'@' -f1)
  git remote set-url origin "https://$TOKEN@github.com/uglyatbeautymolt/ugly-forge.git"
  ```
- **Secret Masking:** Adhere to the same masking rules as in `ugly-stack`.
- **Workflow:** Always commit and push changes.
