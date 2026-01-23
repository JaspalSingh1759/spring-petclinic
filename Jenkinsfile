pipeline {
    agent any

    environment {
        IMAGE_NAME = "mydockeruser/myimage"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    COMMIT_HASH = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
                    sh """
                    docker build -t ${IMAGE_NAME}:latest -t ${IMAGE_NAME}:${COMMIT_HASH} .
                    """
                }
            }
        }

        stage('Login to Docker Hub') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-cred', 
                                                 usernameVariable: 'USER', 
                                                 passwordVariable: 'PASS')]) {
                    sh "echo \$PASS | docker login -u \$USER --password-stdin"
                }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                sh """
                docker push ${IMAGE_NAME}:latest
                docker push ${IMAGE_NAME}:${COMMIT_HASH}
                """
            }
        }
    }

    post {
        always {
            sh "docker logout"
        }
    }
}

