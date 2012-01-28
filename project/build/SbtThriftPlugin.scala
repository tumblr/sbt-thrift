import sbt._
import com.twitter.sbt._

class SbtThriftPlugin(info: ProjectInfo) extends PluginProject(info)
  with TumblrRepos
{
  val jruby = "org.jruby" % "jruby-complete" % "1.6.0"
  override def pomExtra =
    <licenses>
      <license>
        <name>Apache 2</name>
        <url>http://www.apache.org/licenses/LICENSE-2.0.txt</url>
        <distribution>repo</distribution>
      </license>
    </licenses>
}

trait TumblrRepos extends StandardManagedProject {
  // repository setup
  def proxyRepo = environment.get("TUMBLR_REPO")
  override def repositories = {
    val defaultRepos = List(
      "ibiblio" at "http://mirrors.ibiblio.org/pub/mirrors/maven2/",
      "twitter.com" at "http://maven.twttr.com/",
      "powermock-api" at "http://powermock.googlecode.com/svn/repo/",
      "scala-tools.org" at "http://scala-tools.org/repo-releases/",
      "testing.scala-tools.org" at "http://scala-tools.org/repo-releases/testing/",
      "oauth.net" at "http://oauth.googlecode.com/svn/code/maven",
      "download.java.net" at "http://download.java.net/maven/2/",
      "atlassian" at "https://m2proxy.atlassian.com/repository/public/",
      // for netty:
      "jboss" at "http://repository.jboss.org/nexus/content/groups/public/"
    )
    proxyRepo match {
      case Some(url) => localRepos + ("Tumblr Nexus Repo" at url)
      case None => super.repositories ++ Set(defaultRepos: _*)
    }
  }
  override def ivyRepositories = Seq(Resolver.defaultLocal(None)) ++ repositories
  // nexus deployment setup
  def publishUrl = environment.get("TUMBLR_PUBLISH_URL")
  def snapshotDeployRepo = "snapshots"
  def releaseDeployRepo = "releases"

  lazy val publishTo = publishUrl match {
    case Some(url) => if (version.toString.endsWith("SNAPSHOT")) {
      "Tumblr Nexus" at (url + "/" + snapshotDeployRepo)
    } else {
      "Tumblr Nexus" at (url + "/" + releaseDeployRepo)
    }
    case None => throw new Exception("No TUMBLR_PUBLISH_URL specified")
  }
  Credentials(Path.userHome / ".ivy2" / ".credentials", log)
}
