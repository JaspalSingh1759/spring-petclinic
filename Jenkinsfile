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
                sh 'mvn clean package -DskipTests'
            }
        }

        stage('Docker Build') {
            steps {
                script {
                    COMMIT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()

                    sh """
                    docker build \
                      -t ${DOCKER_IMAGE}:latest \
                      -t ${DOCKER_IMAGE}:${COMMIT} .
                    """
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
    }

    post {
        always {
            sh 'docker logout || true'
        }
    }
}

