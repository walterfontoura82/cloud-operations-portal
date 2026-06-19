# force_delete = true permite que Terraform elimine el repositorio ECR aunque todavía contenga imágenes.
# true: al ejecutar terraform destroy, AWS elimina el repositorio y todas sus imágenes.
# false (predeterminado): la eliminación falla si el repositorio no está vacío.
# Es práctico en entornos dev, pero riesgoso en producción porque puede borrar imágenes definitivamente. Una opción más segura es parametrizarlo:
# force_delete = var.force_delete 
resource "aws_ecr_repository" "this" {
  name         = var.repository_name
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = var.repository_name
  }
}