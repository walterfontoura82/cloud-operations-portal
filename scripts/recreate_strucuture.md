** Recrear Estructura para Inciar el despliegue

- Ejecutar el scrip
    cloud-operations-portal/scripts/recreate-lab.sh
- Cambiar el Id de la cuenta en:
    cloud-operations-portal/.github/workflows/terraform-plan.yml el campo:
        role-to-assume: arn:aws:iam::XXXXXXXXXXX:role/cloud-operations-portal-github-actions-terraform-role
    
    cloud-operations-portal/.github/workflows/docker-build.yml en el campo:
        role-to-assume: arn:aws:iam::586789648037:role/cloud-operations-portal-github-actions-terraform-role
    
    