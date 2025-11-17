pipeline {
    agent any

    environment {
        PROJECT_ID = "kubernetes-477004"
        REGION     = "us-central1"
        REPO       = "php-app-repo"
        IMAGE_NAME = "php-app"

        // Unique Docker tag for every build → required for MIG redeploy
        TAG        = "${env.BUILD_NUMBER}"
    }

    stages {

        stage('Checkout PHP Code') {
            steps {
                echo "Pulling code from GitHub..."
                git(
                    url: 'https://github.com/raghu-kadali/php-app.git',
                    branch: 'main'
                )
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "Building Docker image for PHP..."
                sh """
                cd project/application
                docker build -t ${IMAGE_NAME}:${TAG} .
                """
            }
        }

        stage('Tag Docker Image for GAR') {
            steps {
                echo "Tagging image for Artifact Registry..."
                sh """
                docker tag ${IMAGE_NAME}:${TAG} \
                ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE_NAME}:${TAG}
                """
            }
        }

        stage('Push Image to GAR') {
            steps {
                echo "Authenticating Docker with GAR..."
                sh """
                gcloud auth configure-docker ${REGION}-docker.pkg.dev -q
                """

                echo "Pushing image to Artifact Registry..."
                sh """
                docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE_NAME}:${TAG}
                """
            }
        }

        stage('Deploy Infrastructure using Terraform') {
            steps {
                echo "Deploying MIG + ALB using Terraform..."
                sh """
                cd project/terraform
                terraform init
                terraform apply -var="tag=${TAG}" -auto-approve
                """
            }
        }
    }

    post {
        success {
            echo "🎉 CI/CD Pipeline Completed Successfully!"
        }
        failure {
            echo "❌ Pipeline Failed! Check logs."
        }
    }
}
