pipeline {
    agent any

    environment {
        DOCKER_IMAGE = "jaspsing369/petclinic"
    }

    triggers {
        githubPush()
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build JAR (Maven)') {
            steps {
                sh 'mvn clean package -DskipTests -Dcheckstyle.skip=true'

            }
        }

        stage('Docker Build') {
            steps {
                script {
                    COMMIT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()

                    withCredentials([usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DH_USER',
                        passwordVariable: 'DH_PASS'
                    )]) {

                        sh """
                        echo "Logging in to Docker Hub..."
                        echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                        """

                        // Ensure buildx builder exists
                        sh "docker buildx create --use || true"

                        // Multi-arch build + push
                        sh """
                        docker buildx build \
                        --platform linux/amd64,linux/arm64 \
                        -t ${DOCKER_IMAGE}:latest \
                        -t ${DOCKER_IMAGE}:${COMMIT} \
                  --push .
                """
            }
        }
    }
}



        stage('Docker Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'USER',
                    passwordVariable: 'PASS'
                )]) {
                    sh """
                    echo "$PASS" | docker login -u "$USER" --password-stdin
                    docker push ${DOCKER_IMAGE}:latest
                    docker push ${DOCKER_IMAGE}:${COMMIT}
                    """
                }
            }
        }
        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    withCredentials([
                        string(credentialsId: 'aws-access-key', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh "terraform init"
                    }
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir('terraform') {
                    withCredentials([
                        string(credentialsId: 'aws-access-key', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh """
                        terraform apply -auto-approve -var key_name=test
                        """
                    }
                }
            }
        }




    }

    post {
        always {
            sh 'docker logout || true'
        }
    }
}

